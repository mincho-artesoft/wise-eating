import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { AppStoreController } from './app-store/app-store.controller';
import { AppStoreService } from './app-store/app-store.service';
import { DeviceAuthGuard } from './auth/auth';
import { config } from './config';
import { DeviceCheckClient } from './devices/device-check';
import { DevicesController } from './devices/devices.controller';
import { DevicesService } from './devices/devices.service';
import { HealthController } from './health.controller';
import { OpenAIClient } from './openai/openai.client';
import { PrismaModule } from './prisma.service';
import { RealtimeController } from './realtime/realtime.controller';
import { RealtimeService } from './realtime/realtime.service';
import { ReasoningController } from './reasoning/reasoning.controller';
import { ReasoningService } from './reasoning/reasoning.service';
import { WalletService } from './wallet/wallet.service';

@Module({
  imports: [
    PrismaModule,
    JwtModule.registerAsync({ global: true, useFactory: () => ({ secret: config.jwtSecret }) }),
    ThrottlerModule.forRoot({
      throttlers: [{ ttl: 60_000, limit: 120 }],
      // Tests run every request from one address.
      skipIf: () => process.env.THROTTLE_DISABLED === 'true' && process.env.NODE_ENV !== 'production',
    }),
  ],
  controllers: [DevicesController, RealtimeController, ReasoningController, AppStoreController, HealthController],
  providers: [
    WalletService,
    DevicesService,
    DeviceCheckClient,
    RealtimeService,
    ReasoningService,
    AppStoreService,
    OpenAIClient,
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: DeviceAuthGuard },
  ],
})
export class AppModule {}
