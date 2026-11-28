import { Body, Controller, HttpCode, Param, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import type { Device } from '@prisma/client';
import { IsIn, IsObject, IsString, MaxLength } from 'class-validator';
import { CurrentDevice } from '../auth/auth';
import type { AssistantPurpose } from '../assistant/assistant-config';
import { RealtimeService } from './realtime.service';

class ClientSecretDto {
  @IsIn(['assistant', 'constitution']) purpose: AssistantPurpose;
}

class UsageDto {
  @IsString() @MaxLength(128) eventId: string;
  @IsIn(['response', 'transcription']) kind: 'response' | 'transcription';
  @IsObject() usage: Record<string, unknown>;
}

@Controller('realtime')
export class RealtimeController {
  constructor(private readonly realtime: RealtimeService) {}

  @Throttle({ default: { limit: 10, ttl: 60_000 } })
  @Post('client-secret')
  @HttpCode(200)
  clientSecret(@CurrentDevice() device: Device, @Body() body: ClientSecretDto) {
    return this.realtime.createClientSecret(device, body.purpose);
  }

  @Throttle({ default: { limit: 600, ttl: 60_000 } })
  @Post('sessions/:id/usage')
  @HttpCode(200)
  usage(@CurrentDevice() device: Device, @Param('id') id: string, @Body() body: UsageDto) {
    return this.realtime.recordUsage(device, id, body);
  }

  @Post('sessions/:id/end')
  @HttpCode(200)
  end(@CurrentDevice() device: Device, @Param('id') id: string) {
    return this.realtime.end(device, id);
  }
}
