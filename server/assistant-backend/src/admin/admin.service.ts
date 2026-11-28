import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { LedgerDirection, LedgerSource, Prisma, RealtimeSessionStatus } from '@prisma/client';
import { randomUUID } from 'crypto';
import { config } from '../config';
import { PrismaService } from '../prisma.service';
import { WalletService } from '../wallet/wallet.service';

const credits = (milli: bigint | null | undefined) => Number(milli ?? 0n) / 1000;
const usd = (micros: bigint | null | undefined) => Number(micros ?? 0n) / 1_000_000;

function range(days?: string) {
  const d = Math.min(Math.max(Number(days ?? 7) || 7, 1), 365);
  return { days: d, from: new Date(Date.now() - d * 86_400_000) };
}

/**
 * What happens in the assistant, for the owner: devices, voice sessions, usage
 * and its OpenAI cost, credits, grants and purchases. Read-only except credit
 * adjustments and blocking a device. No conversation content is stored, so
 * none is shown.
 */
@Injectable()
export class AdminService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly wallet: WalletService,
  ) {}

  async summary(query: { days?: string; limit?: string }) {
    const { days, from } = range(query.days);
    const limit = Math.min(Math.max(Number(query.limit ?? 30) || 30, 5), 200);
    const where = { createdAt: { gte: from } };

    const [
      devices,
      newDevices,
      activeSessions,
      sessionsInRange,
      usage,
      usageByKind,
      usageByModel,
      usageByPurpose,
      ledgerByDirection,
      ledgerBySource,
      grants,
      grantsInRange,
      purchasesInRange,
      recentUsage,
      recentSessions,
      recentPurchases,
      recentGrants,
      topSpenders,
    ] = await Promise.all([
      this.prisma.device.count(),
      this.prisma.device.count({ where }),
      this.prisma.realtimeSession.count({ where: { status: RealtimeSessionStatus.ACTIVE } }),
      this.prisma.realtimeSession.findMany({ where: { startedAt: { gte: from } }, select: { startedAt: true, endedAt: true, purpose: true } }),
      this.prisma.usageEvent.aggregate({ where, _count: { _all: true }, _sum: { costMicrosUSD: true, chargedMilli: true } }),
      this.prisma.usageEvent.groupBy({ by: ['kind'], where, _count: { _all: true }, _sum: { costMicrosUSD: true, chargedMilli: true } }),
      this.prisma.usageEvent.groupBy({ by: ['model'], where, _count: { _all: true }, _sum: { costMicrosUSD: true, chargedMilli: true } }),
      this.prisma.usageEvent.groupBy({ by: ['purpose'], where, _count: { _all: true }, _sum: { costMicrosUSD: true, chargedMilli: true } }),
      this.prisma.creditLedgerEntry.groupBy({ by: ['direction'], _sum: { amountMilli: true } }),
      this.prisma.creditLedgerEntry.groupBy({ by: ['source', 'direction'], where, _count: { _all: true }, _sum: { amountMilli: true } }),
      this.prisma.onboardingGrant.count(),
      this.prisma.onboardingGrant.count({ where }),
      this.prisma.appStoreTransaction.count({ where }),
      this.prisma.usageEvent.findMany({ where, orderBy: { createdAt: 'desc' }, take: limit }),
      this.prisma.realtimeSession.findMany({ orderBy: { startedAt: 'desc' }, take: limit }),
      this.prisma.appStoreTransaction.findMany({ orderBy: { createdAt: 'desc' }, take: limit }),
      this.prisma.onboardingGrant.findMany({ orderBy: { createdAt: 'desc' }, take: limit }),
      this.prisma.usageEvent.groupBy({
        by: ['deviceId'],
        where,
        _sum: { costMicrosUSD: true, chargedMilli: true },
        _count: { _all: true },
        orderBy: { _sum: { chargedMilli: 'desc' } },
        take: 10,
      }),
    ]);

    const credited = ledgerByDirection.find((r) => r.direction === LedgerDirection.CREDIT)?._sum.amountMilli ?? 0n;
    const debited = ledgerByDirection.find((r) => r.direction === LedgerDirection.DEBIT)?._sum.amountMilli ?? 0n;
    const voiceMinutes = sessionsInRange.reduce((sum, s) => {
      const end = (s.endedAt ?? new Date()).getTime();
      return sum + Math.max(0, end - s.startedAt.getTime()) / 60_000;
    }, 0);
    const group = (r: { _count: { _all: number }; _sum: { costMicrosUSD: bigint | null; chargedMilli: bigint | null } }) => ({
      events: r._count._all,
      costUSD: usd(r._sum.costMicrosUSD),
      credits: credits(r._sum.chargedMilli),
    });

    return {
      range: { days, from: from.toISOString() },
      settings: {
        realtimeModel: config.realtimeModel,
        reasoningModel: config.reasoningModel,
        creditsPerUSD: config.creditsPerUSD,
        onboardingGrantCredits: config.onboardingGrantCredits,
        onboardingGrantEnabled: config.onboardingGrantEnabled,
        deviceCheckRequired: config.deviceCheckRequired,
        appAttestRequired: config.appAttestRequired,
        openAIConfigured: Boolean(config.openAIKey),
      },
      totals: {
        devices,
        newDevices,
        activeSessions,
        voiceSessions: sessionsInRange.length,
        voiceMinutes: Math.round(voiceMinutes * 10) / 10,
        usageEvents: usage._count._all,
        costUSD: usd(usage._sum.costMicrosUSD),
        creditsCharged: credits(usage._sum.chargedMilli),
        creditsOutstanding: credits(credited - debited),
        grantsTotal: grants,
        grantsInRange,
        purchasesInRange,
      },
      usageByKind: usageByKind.map((r) => ({ kind: r.kind, ...group(r) })),
      usageByModel: usageByModel.map((r) => ({ model: r.model, ...group(r) })),
      usageByPurpose: usageByPurpose.map((r) => ({ purpose: r.purpose, ...group(r) })),
      ledgerBySource: ledgerBySource.map((r) => ({
        source: r.source,
        direction: r.direction,
        entries: r._count._all,
        credits: credits(r._sum.amountMilli),
      })),
      topDevices: topSpenders.map((r) => ({ deviceId: r.deviceId, events: r._count._all, costUSD: usd(r._sum.costMicrosUSD), credits: credits(r._sum.chargedMilli) })),
      recentUsage: recentUsage.map((u) => ({
        at: u.createdAt,
        deviceId: u.deviceId,
        kind: u.kind,
        model: u.model,
        purpose: u.purpose,
        sessionId: u.sessionId,
        tokens: {
          textIn: u.inputTextTokens,
          audioIn: u.inputAudioTokens,
          imageIn: u.inputImageTokens,
          cachedIn: u.cachedInputTokens,
          textOut: u.outputTextTokens,
          audioOut: u.outputAudioTokens,
        },
        costUSD: usd(u.costMicrosUSD),
        credits: credits(u.chargedMilli),
      })),
      recentSessions: recentSessions.map((s) => ({
        id: s.id,
        deviceId: s.deviceId,
        purpose: s.purpose,
        model: s.model,
        status: s.status,
        startedAt: s.startedAt,
        endedAt: s.endedAt,
        minutes: Math.round(((s.endedAt ?? new Date()).getTime() - s.startedAt.getTime()) / 6_000) / 10,
        credits: credits(s.chargedMilli),
      })),
      recentPurchases: recentPurchases.map((p) => ({
        at: p.createdAt,
        deviceId: p.deviceId,
        productId: p.productId,
        kind: p.kind,
        environment: p.environment,
        transactionId: p.transactionId,
        revoked: Boolean(p.revocationDate),
      })),
      recentGrants: recentGrants.map((g) => ({
        at: g.createdAt,
        deviceId: g.deviceId,
        credits: g.credits,
        deviceCheckBits: g.deviceCheckBits,
        attested: Boolean(g.attestKeyHash),
      })),
    };
  }

  async devices(query: { search?: string; limit?: string; offset?: string }) {
    const limit = Math.min(Math.max(Number(query.limit ?? 50) || 50, 1), 200);
    const offset = Math.max(Number(query.offset ?? 0) || 0, 0);
    const search = query.search?.trim();
    const where: Prisma.DeviceWhereInput = search
      ? { OR: [{ id: { contains: search } }, { installId: { contains: search } }, { appAccountToken: { contains: search } }] }
      : {};
    const [total, rows] = await Promise.all([
      this.prisma.device.count({ where }),
      this.prisma.device.findMany({ where, orderBy: { lastSeenAt: 'desc' }, skip: offset, take: limit }),
    ]);
    const balances = await Promise.all(rows.map((d) => this.wallet.balanceMilli(d.id)));
    const grants = await this.prisma.onboardingGrant.findMany({ where: { deviceId: { in: rows.map((d) => d.id) } }, select: { deviceId: true } });
    const granted = new Set(grants.map((g) => g.deviceId));
    return {
      total,
      devices: rows.map((d, i) => ({
        id: d.id,
        installId: d.installId,
        createdAt: d.createdAt,
        lastSeenAt: d.lastSeenAt,
        attested: Boolean(d.attestKeyId),
        blocked: d.blocked,
        welcomeCredits: granted.has(d.id),
        credits: credits(balances[i]),
      })),
    };
  }

  async device(id: string) {
    const device = await this.prisma.device.findUnique({ where: { id } });
    if (!device) throw new NotFoundException('Unknown device.');
    const [balance, ledger, usage, sessions, purchases, grant] = await Promise.all([
      this.wallet.balanceMilli(id),
      this.prisma.creditLedgerEntry.findMany({ where: { deviceId: id }, orderBy: { createdAt: 'desc' }, take: 200 }),
      this.prisma.usageEvent.findMany({ where: { deviceId: id }, orderBy: { createdAt: 'desc' }, take: 200 }),
      this.prisma.realtimeSession.findMany({ where: { deviceId: id }, orderBy: { startedAt: 'desc' }, take: 100 }),
      this.prisma.appStoreTransaction.findMany({ where: { deviceId: id }, orderBy: { createdAt: 'desc' }, take: 100 }),
      this.prisma.onboardingGrant.findUnique({ where: { deviceId: id } }),
    ]);
    return {
      device: {
        id: device.id,
        installId: device.installId,
        appAccountToken: device.appAccountToken,
        createdAt: device.createdAt,
        lastSeenAt: device.lastSeenAt,
        attested: Boolean(device.attestKeyId),
        attestedAt: device.attestedAt,
        blocked: device.blocked,
        credits: credits(balance),
      },
      welcomeCredits: grant ? { at: grant.createdAt, credits: grant.credits, deviceCheckBits: grant.deviceCheckBits } : null,
      ledger: ledger.map((l) => ({ at: l.createdAt, direction: l.direction, source: l.source, credits: credits(l.amountMilli), key: l.idempotencyKey, metadata: l.metadata })),
      usage: usage.map((u) => ({ at: u.createdAt, kind: u.kind, model: u.model, purpose: u.purpose, costUSD: usd(u.costMicrosUSD), credits: credits(u.chargedMilli) })),
      sessions: sessions.map((s) => ({ id: s.id, purpose: s.purpose, status: s.status, startedAt: s.startedAt, endedAt: s.endedAt, credits: credits(s.chargedMilli) })),
      purchases: purchases.map((p) => ({ at: p.createdAt, productId: p.productId, environment: p.environment, transactionId: p.transactionId, revoked: Boolean(p.revocationDate) })),
    };
  }

  /** Adds (positive) or removes (negative) credits, with a reason, once per request. */
  async adjustCredits(id: string, body: { credits?: unknown; reason?: unknown }) {
    const amount = Number(body.credits);
    const reason = String(body.reason ?? '').trim().slice(0, 200);
    if (!Number.isFinite(amount) || amount === 0 || Math.abs(amount) > 100_000) throw new BadRequestException('credits must be a non-zero number up to 100000');
    if (!reason) throw new BadRequestException('a reason is required');
    const device = await this.prisma.device.findUnique({ where: { id } });
    if (!device) throw new NotFoundException('Unknown device.');
    const milli = BigInt(Math.round(Math.abs(amount) * 1000));
    const key = `admin:${randomUUID()}`;
    if (amount > 0) {
      await this.wallet.credit(id, milli, LedgerSource.ADMIN_ADJUSTMENT, key, { reason });
    } else {
      await this.prisma.creditLedgerEntry.create({
        data: { deviceId: id, direction: LedgerDirection.DEBIT, source: LedgerSource.ADMIN_ADJUSTMENT, amountMilli: milli, idempotencyKey: key, metadata: { reason } },
      });
    }
    return { device: id, credits: credits(await this.wallet.balanceMilli(id)) };
  }

  async setBlocked(id: string, blocked: unknown) {
    const device = await this.prisma.device.update({ where: { id }, data: { blocked: Boolean(blocked) } }).catch(() => null);
    if (!device) throw new NotFoundException('Unknown device.');
    return { device: id, blocked: device.blocked };
  }
}

