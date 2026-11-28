import { Body, Controller, Get, HttpCode, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import type { Device } from '@prisma/client';
import { IsOptional, IsString, MaxLength } from 'class-validator';
import { CurrentDevice, Public } from '../auth/auth';
import { WalletService } from '../wallet/wallet.service';
import { DevicesService } from './devices.service';

class RegisterDto {
  @IsString() @MaxLength(64) installId: string;
  @IsOptional() @IsString() @MaxLength(128) keyId?: string;
  @IsOptional() @IsString() @MaxLength(20000) attestation?: string;
  @IsOptional() @IsString() @MaxLength(128) challenge?: string;
}

class GrantDto {
  @IsOptional() @IsString() @MaxLength(8000) deviceCheckToken?: string;
  @IsOptional() @IsString() @MaxLength(4000) assertion?: string;
  @IsOptional() @IsString() @MaxLength(128) challenge?: string;
}

@Controller()
export class DevicesController {
  constructor(
    private readonly devices: DevicesService,
    private readonly wallet: WalletService,
  ) {}

  @Public()
  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @Post('devices/challenge')
  @HttpCode(200)
  challenge() {
    return { challenge: this.devices.challenges.issue() };
  }

  @Public()
  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('devices/register')
  @HttpCode(200)
  register(@Body() body: RegisterDto) {
    return this.devices.register(body);
  }

  @Get('wallet')
  async getWallet(@CurrentDevice() device: Device) {
    return { wallet: await this.wallet.view(device.id), onboardingGrant: await this.devices.grantState(device) };
  }

  @Throttle({ default: { limit: 5, ttl: 60_000 } })
  @Post('grants/onboarding')
  @HttpCode(200)
  claim(@CurrentDevice() device: Device, @Body() body: GrantDto) {
    return this.devices.claimOnboardingGrant(device, body);
  }
}
