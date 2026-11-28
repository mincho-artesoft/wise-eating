import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  ServiceUnavailableException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Device, LedgerSource } from '@prisma/client';
import { randomBytes } from 'crypto';
import { readFileSync } from 'fs';
import { config, MILLI } from '../config';
import { PrismaService } from '../prisma.service';
import { WalletService } from '../wallet/wallet.service';
import { AppAttestError, appId, sha256, verifyAssertion, verifyAttestation } from './app-attest';
import { DeviceCheckClient } from './device-check';

export type GrantState = 'available' | 'used' | 'disabled';

/** Single-use server challenges for App Attest, kept in memory for 5 minutes. */
export class ChallengeStore {
  private readonly items = new Map<string, number>();

  issue(): string {
    this.sweep();
    const value = randomBytes(32).toString('base64');
    this.items.set(value, Date.now() + 5 * 60_000);
    return value;
  }

  consume(value: string | undefined): Buffer {
    if (!value) throw new BadRequestException('challenge is required');
    const expires = this.items.get(value);
    this.items.delete(value);
    if (!expires || expires < Date.now()) throw new ForbiddenException('Unknown or expired challenge.');
    return Buffer.from(value, 'base64');
  }

  private sweep() {
    const now = Date.now();
    for (const [k, v] of this.items) if (v < now) this.items.delete(k);
  }
}

@Injectable()
export class DevicesService {
  private readonly logger = new Logger(DevicesService.name);
  readonly challenges = new ChallengeStore();
  private rootPem?: Buffer;

  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly wallet: WalletService,
    private readonly deviceCheck: DeviceCheckClient,
  ) {}

  private appId() {
    if (!config.appleTeamId || !config.appleBundleId) {
      throw new ServiceUnavailableException('APPLE_TEAM_ID and APPLE_BUNDLE_ID are required for App Attest.');
    }
    return appId(config.appleTeamId, config.appleBundleId);
  }

  private root(): Buffer {
    this.rootPem ??= readFileSync(config.appAttestRootPath);
    return this.rootPem;
  }

  /** Test hook: use another root certificate. */
  setAttestationRoot(pem: Buffer) {
    this.rootPem = pem;
  }

  async register(input: { installId: string; keyId?: string; attestation?: string; challenge?: string }) {
    if (!/^[A-Za-z0-9-]{16,64}$/.test(input.installId)) throw new BadRequestException('installId is invalid');

    let attested: { keyId: string; publicKey: Uint8Array<ArrayBuffer> } | undefined;
    if (input.attestation && input.keyId) {
      const challenge = this.challenges.consume(input.challenge);
      try {
        const result = verifyAttestation({
          attestation: Buffer.from(input.attestation, 'base64'),
          challenge,
          keyId: input.keyId,
          appId: this.appId(),
          rootPem: this.root(),
          allowDevelopment: config.appAttestAllowDevelopment,
        });
        attested = { keyId: result.keyId, publicKey: new Uint8Array(result.publicKey) };
      } catch (error) {
        if (error instanceof AppAttestError) throw new ForbiddenException(`App Attest failed: ${error.message}`);
        throw error;
      }
    } else if (config.appAttestRequired) {
      throw new ForbiddenException('App Attest is required.');
    }

    if (attested) {
      const owner = await this.prisma.device.findUnique({ where: { attestKeyId: attested.keyId } });
      if (owner && owner.installId !== input.installId) throw new ConflictException('This key belongs to another install.');
    }

    const device = await this.prisma.device.upsert({
      where: { installId: input.installId },
      create: {
        installId: input.installId,
        attestKeyId: attested?.keyId,
        attestPublicKey: attested?.publicKey,
        attestedAt: attested ? new Date() : undefined,
      },
      update: {
        lastSeenAt: new Date(),
        // A reinstall makes a new App Attest key for the same install id.
        ...(attested
          ? { attestKeyId: attested.keyId, attestPublicKey: attested.publicKey, attestCounter: 0, attestedAt: new Date() }
          : {}),
      },
    });
    if (device.blocked) throw new ForbiddenException('This device is blocked.');

    const token = await this.jwt.signAsync({ sub: device.id }, { expiresIn: '30d' });
    return {
      token,
      deviceId: device.id,
      appAccountToken: device.appAccountToken,
      wallet: await this.wallet.view(device.id),
      onboardingGrant: await this.grantState(device),
    };
  }

  /** Checks an App Attest assertion over a server challenge for this device. */
  async requireAssertion(device: Device, assertion?: string, challenge?: string): Promise<void> {
    if (!device.attestPublicKey) {
      if (config.appAttestRequired) throw new ForbiddenException('App Attest is required.');
      return;
    }
    if (!assertion) {
      if (config.appAttestRequired) throw new ForbiddenException('An App Attest assertion is required.');
      return;
    }
    const clientData = this.challenges.consume(challenge);
    try {
      const counter = verifyAssertion({
        assertion: Buffer.from(assertion, 'base64'),
        clientData,
        publicKey: Buffer.from(device.attestPublicKey),
        previousCounter: device.attestCounter,
        appId: this.appId(),
      });
      await this.prisma.device.update({ where: { id: device.id }, data: { attestCounter: counter } });
    } catch (error) {
      if (error instanceof AppAttestError) throw new ForbiddenException(`App Attest failed: ${error.message}`);
      throw error;
    }
  }

  async grantState(device: Device): Promise<GrantState> {
    if (!config.onboardingGrantEnabled) return 'disabled';
    const used = await this.prisma.onboardingGrant.findFirst({
      where: {
        OR: [
          { deviceId: device.id },
          { installId: device.installId },
          ...(device.attestKeyId ? [{ attestKeyHash: sha256(Buffer.from(device.attestKeyId)).toString('hex') }] : []),
        ],
      },
    });
    return used ? 'used' : 'available';
  }

  /**
   * The onboarding grant, once per device: our own records first, then Apple's
   * DeviceCheck bit 0, which survives reinstalling and erasing the app.
   */
  async claimOnboardingGrant(device: Device, input: { deviceCheckToken?: string; assertion?: string; challenge?: string }) {
    if (!config.onboardingGrantEnabled) throw new ForbiddenException('The welcome credits are not offered.');
    await this.requireAssertion(device, input.assertion, input.challenge);
    if ((await this.grantState(device)) === 'used') throw new ConflictException('The welcome credits were already given.');

    let bits: { bit0: boolean; bit1: boolean } | undefined;
    if (this.deviceCheck.isConfigured && input.deviceCheckToken) {
      bits = await this.deviceCheck.query(input.deviceCheckToken);
      if (bits.bit0) throw new ConflictException('The welcome credits were already given on this device.');
    } else if (config.deviceCheckRequired) {
      throw new ForbiddenException('DeviceCheck is required.');
    }

    const credits = config.onboardingGrantCredits;
    try {
      await this.wallet.serializable(async (tx) => {
        await tx.onboardingGrant.create({
          data: {
            deviceId: device.id,
            installId: device.installId,
            attestKeyHash: device.attestKeyId ? sha256(Buffer.from(device.attestKeyId)).toString('hex') : null,
            deviceCheckBits: bits ? `${Number(bits.bit0)}${Number(bits.bit1)}` : null,
            credits,
          },
        });
        await this.wallet.credit(device.id, BigInt(credits) * MILLI, LedgerSource.ONBOARDING_GRANT, `onboarding:${device.id}`, { credits }, tx);
      });
    } catch (error) {
      if ((error as { code?: string }).code === 'P2002') throw new ConflictException('The welcome credits were already given.');
      throw error;
    }

    if (bits && input.deviceCheckToken) {
      try {
        await this.deviceCheck.update(input.deviceCheckToken, { bit0: true, bit1: bits.bit1 });
      } catch {
        // Our own rows still block this install and key; Apple's bit is retried on the next claim.
        this.logger.warn(`DeviceCheck bit not set for device ${device.id}`);
      }
    }
    return { granted: credits, wallet: await this.wallet.view(device.id) };
  }
}
