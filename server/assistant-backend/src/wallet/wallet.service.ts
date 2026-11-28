import { Injectable } from '@nestjs/common';
import { LedgerDirection, LedgerSource, Prisma } from '@prisma/client';
import { MILLI } from '../config';
import { PrismaService } from '../prisma.service';

type Tx = Prisma.TransactionClient;

export interface BalanceView {
  /** Whole credits, rounded down, for display. */
  credits: number;
  balanceMilli: string;
}

/** The credit ledger: append-only rows; the balance is their sum. */
@Injectable()
export class WalletService {
  constructor(private readonly prisma: PrismaService) {}

  async balanceMilli(deviceId: string, tx: Tx = this.prisma): Promise<bigint> {
    const rows = await tx.creditLedgerEntry.groupBy({
      by: ['direction'],
      where: { deviceId },
      _sum: { amountMilli: true },
    });
    let total = 0n;
    for (const r of rows) {
      const sum = r._sum.amountMilli ?? 0n;
      total += r.direction === LedgerDirection.CREDIT ? sum : -sum;
    }
    return total;
  }

  async view(deviceId: string): Promise<BalanceView> {
    const milli = await this.balanceMilli(deviceId);
    return { credits: Number(milli / MILLI), balanceMilli: milli.toString() };
  }

  /** Adds credits once per idempotency key; returns false when already applied. */
  async credit(
    deviceId: string,
    amountMilli: bigint,
    source: LedgerSource,
    idempotencyKey: string,
    metadata?: Prisma.InputJsonValue,
    tx?: Tx,
  ): Promise<boolean> {
    const run = async (t: Tx) => {
      const existing = await t.creditLedgerEntry.findUnique({ where: { idempotencyKey } });
      if (existing) return false;
      await t.creditLedgerEntry.create({
        data: { deviceId, direction: LedgerDirection.CREDIT, source, amountMilli, idempotencyKey, metadata },
      });
      return true;
    };
    return tx ? run(tx) : this.serializable(run);
  }

  /**
   * Charges up to the balance (never below zero) once per idempotency key.
   * Returns what was charged and whether the balance is now empty.
   */
  async debit(
    deviceId: string,
    amountMilli: bigint,
    idempotencyKey: string,
    metadata?: Prisma.InputJsonValue,
    tx?: Tx,
  ): Promise<{ chargedMilli: bigint; balanceMilli: bigint; insufficient: boolean; duplicate: boolean }> {
    const run = async (t: Tx) => {
      const existing = await t.creditLedgerEntry.findUnique({ where: { idempotencyKey } });
      const before = await this.balanceMilli(deviceId, t);
      if (existing) {
        return { chargedMilli: existing.amountMilli, balanceMilli: before, insufficient: before <= 0n, duplicate: true };
      }
      const charge = amountMilli <= 0n ? 0n : amountMilli > before ? (before > 0n ? before : 0n) : amountMilli;
      if (charge > 0n) {
        await t.creditLedgerEntry.create({
          data: {
            deviceId,
            direction: LedgerDirection.DEBIT,
            source: LedgerSource.USAGE,
            amountMilli: charge,
            idempotencyKey,
            metadata,
          },
        });
      }
      const after = before - charge;
      return { chargedMilli: charge, balanceMilli: after, insufficient: amountMilli > before || after <= 0n, duplicate: false };
    };
    return tx ? run(tx) : this.serializable(run);
  }

  /** Serializable transaction with retry on write conflicts (P2034). */
  async serializable<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    for (let attempt = 0; ; attempt++) {
      try {
        return await this.prisma.$transaction(fn, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
      } catch (error) {
        const code = (error as { code?: string }).code;
        if ((code === 'P2034' || code === 'P2002') && attempt < 4) continue;
        throw error;
      }
    }
  }
}
