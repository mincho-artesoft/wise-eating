import { ForbiddenException, Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { importPKCS8, SignJWT } from 'jose';
import { config } from '../config';

export interface TwoBits {
  bit0: boolean;
  bit1: boolean;
  /** "YYYY-MM" of the last update, or undefined when never set. */
  lastUpdate?: string;
}

/**
 * Apple DeviceCheck: two bits per device and developer team that survive
 * reinstalling the app. Bit 0 = the onboarding grant was given.
 */
@Injectable()
export class DeviceCheckClient {
  private readonly logger = new Logger(DeviceCheckClient.name);

  get isConfigured() {
    return Boolean(config.appleTeamId && config.deviceCheckKeyId && config.deviceCheckPrivateKey);
  }

  private async token(): Promise<string> {
    const key = await importPKCS8(config.deviceCheckPrivateKey, 'ES256');
    return new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: config.deviceCheckKeyId })
      .setIssuer(config.appleTeamId)
      .setIssuedAt()
      .sign(key);
  }

  private async call(path: string, body: Record<string, unknown>): Promise<Response> {
    if (!this.isConfigured) throw new ServiceUnavailableException('DeviceCheck is not configured.');
    return fetch(`${config.deviceCheckBaseURL}/${path}`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${await this.token()}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...body, transaction_id: randomUUID(), timestamp: Date.now() }),
    });
  }

  async query(deviceToken: string): Promise<TwoBits> {
    const response = await this.call('query_two_bits', { device_token: deviceToken });
    const text = await response.text();
    // Apple answers 400 for a token that is malformed, forged or not from this team.
    if (response.status === 400) throw new ForbiddenException('The DeviceCheck token is not valid.');
    if (response.status !== 200) {
      this.logger.warn(`DeviceCheck query failed: ${response.status}`);
      throw new ServiceUnavailableException('DeviceCheck query failed.');
    }
    // Apple answers 200 with a plain sentence when the bits were never set.
    if (!text.trim().startsWith('{')) return { bit0: false, bit1: false };
    const json = JSON.parse(text) as { bit0?: boolean; bit1?: boolean; last_update_time?: string };
    return { bit0: Boolean(json.bit0), bit1: Boolean(json.bit1), lastUpdate: json.last_update_time };
  }

  async update(deviceToken: string, bits: { bit0: boolean; bit1: boolean }): Promise<void> {
    const response = await this.call('update_two_bits', { device_token: deviceToken, bit0: bits.bit0, bit1: bits.bit1 });
    if (response.status === 400) throw new ForbiddenException('The DeviceCheck token is not valid.');
    if (response.status !== 200) {
      this.logger.warn(`DeviceCheck update failed: ${response.status}`);
      throw new ServiceUnavailableException('DeviceCheck update failed.');
    }
  }
}
