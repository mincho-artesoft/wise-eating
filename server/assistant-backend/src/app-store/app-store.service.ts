import { BadRequestException, ForbiddenException, Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import {
  Environment,
  JWSTransactionDecodedPayload,
  NotificationTypeV2,
  ResponseBodyV2DecodedPayload,
  SignedDataVerifier,
  VerificationException,
} from '@apple/app-store-server-library';
import { Device, LedgerDirection, LedgerSource } from '@prisma/client';
import { readFileSync } from 'fs';
import { config, MILLI, PRODUCTS } from '../config';
import { PrismaService } from '../prisma.service';
import { WalletService } from '../wallet/wallet.service';

function decodeUnverified<T>(jws: string): T {
  const [, payload] = jws.split('.');
  if (!payload) throw new BadRequestException('Invalid JWS.');
  return JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')) as T;
}

function environmentOf(value?: string): Environment {
  switch (value) {
    case 'Production':
      return Environment.PRODUCTION;
    case 'Xcode':
      return Environment.XCODE;
    case 'LocalTesting':
      return Environment.LOCAL_TESTING;
    default:
      return Environment.SANDBOX;
  }
}

/**
 * Credit packs and subscriptions, verified with Apple's App Store Server
 * Library. Each transaction id grants once; refunds take the credits back.
 */
@Injectable()
export class AppStoreService {
  private readonly logger = new Logger(AppStoreService.name);
  private readonly verifiers = new Map<Environment, SignedDataVerifier>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly wallet: WalletService,
  ) {}

  private verifier(environment: Environment): SignedDataVerifier {
    const existing = this.verifiers.get(environment);
    if (existing) return existing;
    if (!config.appleBundleId) throw new ServiceUnavailableException('APPLE_BUNDLE_ID is required.');
    if (environment === Environment.PRODUCTION && !config.appleAppAppleId) {
      throw new ServiceUnavailableException('APPLE_APP_APPLE_ID is required in production.');
    }
    const roots = config.appleRootCertificatePaths.map((p) => readFileSync(p));
    const verifier = new SignedDataVerifier(roots, true, environment, config.appleBundleId, config.appleAppAppleId);
    this.verifiers.set(environment, verifier);
    return verifier;
  }

  async decodeTransaction(signed: string): Promise<JWSTransactionDecodedPayload> {
    const hint = decodeUnverified<JWSTransactionDecodedPayload>(signed);
    const env = environmentOf(hint.environment as string | undefined);
    if (env === Environment.XCODE || env === Environment.LOCAL_TESTING || config.allowUnverifiedStoreKit) {
      if (!config.allowUnverifiedStoreKit) throw new ForbiddenException('Local StoreKit transactions are not accepted here.');
      return hint;
    }
    try {
      return await this.verifier(env).verifyAndDecodeTransaction(signed);
    } catch (error) {
      if (error instanceof VerificationException) throw new ForbiddenException('StoreKit verification failed.');
      throw error;
    }
  }

  async decodeNotification(signed: string): Promise<ResponseBodyV2DecodedPayload> {
    const hint = decodeUnverified<ResponseBodyV2DecodedPayload>(signed);
    if (config.allowUnverifiedStoreKit) return hint;
    try {
      return await this.verifier(environmentOf(hint.data?.environment as string | undefined)).verifyAndDecodeNotification(signed);
    } catch (error) {
      if (error instanceof VerificationException) throw new ForbiddenException('Notification verification failed.');
      throw error;
    }
  }

  /** The app reports a purchase it just made. */
  async recordFromApp(device: Device, signedTransactionInfo: string) {
    const tx = await this.decodeTransaction(signedTransactionInfo);
    if (tx.bundleId && config.appleBundleId && tx.bundleId !== config.appleBundleId) throw new ForbiddenException('Wrong app.');
    if (tx.appAccountToken && tx.appAccountToken !== device.appAccountToken) {
      // Bought on another install of the same person: credit the device that bought it.
      const owner = await this.prisma.device.findUnique({ where: { appAccountToken: tx.appAccountToken } });
      if (owner) return this.apply(owner, tx);
    }
    return this.apply(device, tx);
  }

  /** App Store Server Notifications V2. */
  async handleNotification(signedPayload: string) {
    const note = await this.decodeNotification(signedPayload);
    const signedTx = note.data?.signedTransactionInfo;
    if (!signedTx) return { ok: true };
    const tx = await this.decodeTransaction(signedTx);
    const device = tx.appAccountToken
      ? await this.prisma.device.findUnique({ where: { appAccountToken: tx.appAccountToken } })
      : await this.deviceForOriginal(tx.originalTransactionId);
    if (!device) {
      this.logger.warn(`notification ${note.notificationType} for an unknown device`);
      return { ok: true };
    }
    switch (note.notificationType) {
      case NotificationTypeV2.SUBSCRIBED:
      case NotificationTypeV2.DID_RENEW:
      case NotificationTypeV2.ONE_TIME_CHARGE:
      case NotificationTypeV2.OFFER_REDEEMED:
        await this.apply(device, tx);
        break;
      case NotificationTypeV2.REFUND:
      case NotificationTypeV2.REVOKE:
        await this.reverse(device, tx);
        break;
      default:
        break;
    }
    return { ok: true };
  }

  private async deviceForOriginal(originalTransactionId?: string) {
    if (!originalTransactionId) return null;
    const row = await this.prisma.appStoreTransaction.findFirst({ where: { originalTransactionId }, include: { device: true } });
    return row?.device ?? null;
  }

  private async apply(device: Device, tx: JWSTransactionDecodedPayload) {
    const product = tx.productId ? PRODUCTS[tx.productId] : undefined;
    if (!product || !tx.transactionId) throw new BadRequestException('Unknown product.');
    if (tx.revocationDate) return { granted: 0, wallet: await this.wallet.view(device.id) };
    const transactionId = tx.transactionId;
    let granted = 0;
    await this.wallet.serializable(async (db) => {
      await db.appStoreTransaction.upsert({
        where: { transactionId },
        create: {
          deviceId: device.id,
          transactionId,
          originalTransactionId: tx.originalTransactionId ?? transactionId,
          productId: tx.productId!,
          kind: product.kind,
          environment: String(tx.environment ?? ''),
          purchaseDate: tx.purchaseDate ? new Date(tx.purchaseDate) : null,
          expiresDate: tx.expiresDate ? new Date(tx.expiresDate) : null,
        },
        update: {},
      });
      // Every pack purchase and every subscription period has its own transaction id.
      const added = await this.wallet.credit(
        device.id,
        BigInt(product.credits) * MILLI,
        product.kind === 'pack' ? LedgerSource.CREDIT_PACK : LedgerSource.SUBSCRIPTION_GRANT,
        `appstore:${transactionId}`,
        { productId: tx.productId, credits: product.credits },
        db,
      );
      if (added) granted = product.credits;
    });
    return { granted, wallet: await this.wallet.view(device.id) };
  }

  private async reverse(device: Device, tx: JWSTransactionDecodedPayload) {
    if (!tx.transactionId) return;
    const grant = await this.prisma.creditLedgerEntry.findUnique({ where: { idempotencyKey: `appstore:${tx.transactionId}` } });
    if (!grant || grant.direction !== LedgerDirection.CREDIT) return;
    await this.wallet.debit(device.id, grant.amountMilli, `appstore-reversal:${tx.transactionId}`, { transactionId: tx.transactionId });
    await this.prisma.appStoreTransaction.updateMany({
      where: { transactionId: tx.transactionId },
      data: { revocationDate: tx.revocationDate ? new Date(tx.revocationDate) : new Date() },
    });
  }
}
