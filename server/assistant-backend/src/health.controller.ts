import { Controller, Get } from '@nestjs/common';
import { Public } from './auth/auth';
import { config } from './config';
import { PrismaService } from './prisma.service';

@Controller('health')
export class HealthController {
  constructor(private readonly prisma: PrismaService) {}

  @Public()
  @Get('ready')
  async ready() {
    await this.prisma.$queryRaw`SELECT 1`;
    return { ok: true, openAIConfigured: Boolean(config.openAIKey), realtimeModel: config.realtimeModel, reasoningModel: config.reasoningModel };
  }
}
