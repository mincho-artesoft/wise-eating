import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import type { Device } from '@prisma/client';
import { IsArray, IsIn, IsOptional, IsString, MaxLength } from 'class-validator';
import { CurrentDevice } from '../auth/auth';
import type { ReasoningPurpose } from '../assistant/assistant-config';
import { ReasoningService } from './reasoning.service';

class ReasoningDto {
  @IsIn(['assistant', 'plan', 'photo']) purpose: ReasoningPurpose;
  @IsString() @MaxLength(128) requestId: string;
  @IsArray() input: unknown[];
  @IsOptional() @IsString() @MaxLength(9_000_000) imageJPEGBase64?: string;
}

@Controller('reasoning')
export class ReasoningController {
  constructor(private readonly reasoning: ReasoningService) {}

  @Throttle({ default: { limit: 30, ttl: 60_000 } })
  @Post()
  @HttpCode(200)
  respond(@CurrentDevice() device: Device, @Body() body: ReasoningDto) {
    return this.reasoning.respond(device, body);
  }
}
