import { HttpException, HttpStatus, Injectable, Logger, NotFoundException, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { Device, RealtimeSessionStatus, UsageKind } from '@prisma/client';
import { createHash } from 'crypto';
import { AssistantPurpose, realtimeInstructions, realtimeTools } from '../assistant/assistant-config';
import { chargeMilliForCost, config, MILLI } from '../config';
import { OpenAIClient } from '../openai/openai.client';
import { PrismaService } from '../prisma.service';
import { WalletService } from '../wallet/wallet.service';
import { breakdown, costMicros, OpenAIUsage } from './pricing';

export class InsufficientCreditsException extends HttpException {
  constructor(balanceMilli: bigint) {
    super(
      { statusCode: 402, error: 'insufficient_credits', message: 'Not enough credits.', balanceMilli: balanceMilli.toString() },
      HttpStatus.PAYMENT_REQUIRED,
    );
  }
}

export function safetyIdentifier(deviceId: string) {
  return createHash('sha256').update(`ayura-assistant:${deviceId}`).digest('hex');
}

interface ClientSecretResponse {
  value?: string;
  expires_at?: number;
  client_secret?: { value?: string; expires_at?: number };
  session?: { id?: string };
}

@Injectable()
export class RealtimeService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RealtimeService.name);
  private sweeper?: NodeJS.Timeout;

  constructor(
    private readonly prisma: PrismaService,
    private readonly wallet: WalletService,
    private readonly openai: OpenAIClient,
  ) {}

  onModuleInit() {
    if (process.env.NODE_ENV !== 'test') {
      this.sweeper = setInterval(() => void this.sweepExpired().catch(() => undefined), 60_000);
    }
  }

  onModuleDestroy() {
    if (this.sweeper) clearInterval(this.sweeper);
  }

  /** The session config sent to OpenAI; instructions and tools come only from the server. */
  sessionConfig(purpose: AssistantPurpose) {
    return {
      type: 'realtime',
      model: config.realtimeModel,
      instructions: realtimeInstructions(purpose),
      output_modalities: ['audio'],
      max_output_tokens: 1024,
      tool_choice: 'auto',
      tools: realtimeTools(purpose),
      audio: {
        input: {
          format: { type: 'audio/pcm', rate: 24000 },
          noise_reduction: { type: 'near_field' },
          transcription: { model: config.transcriptionModel },
          turn_detection: { type: 'semantic_vad', eagerness: 'medium', create_response: true, interrupt_response: true },
        },
        output: { format: { type: 'audio/pcm', rate: 24000 }, voice: config.realtimeVoice },
      },
    };
  }

  async createClientSecret(device: Device, purpose: AssistantPurpose) {
    // One voice session per device: end the previous one first.
    const open = await this.prisma.realtimeSession.findMany({ where: { deviceId: device.id, status: RealtimeSessionStatus.ACTIVE } });
    for (const s of open) await this.end(device, s.id);

    const balance = await this.wallet.balanceMilli(device.id);
    if (balance < BigInt(Math.ceil(config.minCreditsToStart * 1000))) throw new InsufficientCreditsException(balance);

    const session = await this.prisma.realtimeSession.create({
      data: { deviceId: device.id, purpose, model: config.realtimeModel },
    });
    const response = await this.openai.post<ClientSecretResponse>('/realtime/client_secrets', {
      expires_after: { anchor: 'created_at', seconds: config.clientSecretSeconds },
      session: this.sessionConfig(purpose),
    });
    const value = response.value ?? response.client_secret?.value;
    const expiresAt = response.expires_at ?? response.client_secret?.expires_at;
    if (!value) {
      await this.prisma.realtimeSession.update({ where: { id: session.id }, data: { status: RealtimeSessionStatus.ENDED, endedAt: new Date() } });
      throw new HttpException('No client secret from OpenAI.', HttpStatus.BAD_GATEWAY);
    }
    await this.prisma.realtimeSession.update({
      where: { id: session.id },
      data: { secretExpiresAt: expiresAt ? new Date(expiresAt * 1000) : null },
    });
    return {
      sessionId: session.id,
      clientSecret: value,
      expiresAt,
      model: config.realtimeModel,
      maxMinutes: config.voiceSessionMaxMinutes,
      safetyIdentifier: safetyIdentifier(device.id),
      wallet: await this.wallet.view(device.id),
    };
  }

  /** Records one usage report from the app (idempotent per event id). */
  async recordUsage(
    device: Device,
    sessionId: string,
    event: { eventId: string; kind: 'response' | 'transcription'; usage: OpenAIUsage },
  ) {
    const session = await this.prisma.realtimeSession.findFirst({ where: { id: sessionId, deviceId: device.id } });
    if (!session) throw new NotFoundException('Unknown voice session.');
    const ageMinutes = (Date.now() - session.startedAt.getTime()) / 60_000;
    if (session.status !== RealtimeSessionStatus.ACTIVE || ageMinutes > config.voiceSessionMaxMinutes) {
      return { insufficientCredits: true, ended: true, wallet: await this.wallet.view(device.id) };
    }
    const model = event.kind === 'transcription' ? config.transcriptionModel : session.model;
    const cost = costMicros(model, event.usage);
    const charge = chargeMilliForCost(cost);
    const key = `rt:${session.id}:${event.kind}:${event.eventId}`;
    const t = breakdown(event.usage);

    const result = await this.wallet.serializable(async (tx) => {
      const existing = await tx.usageEvent.findUnique({ where: { idempotencyKey: key } });
      if (existing) return { duplicate: true, insufficient: false };
      const debit = await this.wallet.debit(device.id, charge, key, { sessionId, kind: event.kind }, tx);
      await tx.usageEvent.create({
        data: {
          deviceId: device.id,
          kind: event.kind === 'transcription' ? UsageKind.REALTIME_TRANSCRIPTION : UsageKind.REALTIME_RESPONSE,
          model,
          purpose: session.purpose,
          sessionId,
          inputTextTokens: t.textIn,
          inputAudioTokens: t.audioIn,
          inputImageTokens: t.imageIn,
          cachedInputTokens: t.cachedText + t.cachedAudio,
          outputTextTokens: t.textOut,
          outputAudioTokens: t.audioOut,
          costMicrosUSD: cost,
          chargedMilli: debit.chargedMilli,
          idempotencyKey: key,
        },
      });
      await tx.realtimeSession.update({ where: { id: session.id }, data: { chargedMilli: { increment: debit.chargedMilli } } });
      return { duplicate: false, insufficient: debit.insufficient };
    });
    return { insufficientCredits: result.insufficient, ended: false, wallet: await this.wallet.view(device.id) };
  }

  /** Ends a session and charges the per-minute floor where reported usage was lower. */
  async end(device: Device, sessionId: string) {
    const session = await this.prisma.realtimeSession.findFirst({ where: { id: sessionId, deviceId: device.id } });
    if (!session) throw new NotFoundException('Unknown voice session.');
    if (session.status !== RealtimeSessionStatus.ACTIVE) return { wallet: await this.wallet.view(device.id) };
    const endedAt = new Date();
    const minutes = Math.min(
      Math.max(1, Math.ceil((endedAt.getTime() - session.startedAt.getTime()) / 60_000)),
      config.voiceSessionMaxMinutes,
    );
    const floor = BigInt(Math.ceil(minutes * config.voiceFloorCreditsPerMinute * 1000));
    await this.wallet.serializable(async (tx) => {
      const fresh = await tx.realtimeSession.findUnique({ where: { id: session.id } });
      if (!fresh || fresh.status !== RealtimeSessionStatus.ACTIVE) return;
      let extra = 0n;
      if (fresh.chargedMilli < floor) {
        const key = `rt:${session.id}:floor`;
        const debit = await this.wallet.debit(device.id, floor - fresh.chargedMilli, key, { sessionId, minutes }, tx);
        extra = debit.chargedMilli;
        await tx.usageEvent.create({
          data: {
            deviceId: device.id,
            kind: UsageKind.REALTIME_MINUTE_FLOOR,
            model: session.model,
            purpose: session.purpose,
            sessionId,
            costMicrosUSD: 0n,
            chargedMilli: extra,
            idempotencyKey: key,
          },
        });
      }
      await tx.realtimeSession.update({
        where: { id: session.id },
        data: { status: RealtimeSessionStatus.ENDED, endedAt, chargedMilli: { increment: extra } },
      });
    });
    return { minutes, wallet: await this.wallet.view(device.id) };
  }

  async sweepExpired() {
    const cutoff = new Date(Date.now() - config.voiceSessionMaxMinutes * 60_000);
    const stale = await this.prisma.realtimeSession.findMany({
      where: { status: RealtimeSessionStatus.ACTIVE, startedAt: { lt: cutoff } },
      include: { device: true },
      take: 100,
    });
    for (const s of stale) {
      await this.end(s.device, s.id).catch((e) => this.logger.warn(`sweep ${s.id}: ${e}`));
    }
    return stale.length;
  }
}

export const milliToCredits = (milli: bigint) => Number(milli / MILLI);
