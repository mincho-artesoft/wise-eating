import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import type { Device } from '@prisma/client';
import { IsString, MaxLength } from 'class-validator';
import { CurrentDevice, Public } from '../auth/auth';
import { AppStoreService } from './app-store.service';

class TransactionDto {
  @IsString() @MaxLength(20000) signedTransactionInfo: string;
}

class NotificationDto {
  @IsString() @MaxLength(60000) signedPayload: string;
}

@Controller('app-store')
export class AppStoreController {
  constructor(private readonly appStore: AppStoreService) {}

  @Post('transactions')
  @HttpCode(200)
  record(@CurrentDevice() device: Device, @Body() body: TransactionDto) {
    return this.appStore.recordFromApp(device, body.signedTransactionInfo);
  }

  @Public()
  @Post('notifications')
  @HttpCode(200)
  notify(@Body() body: NotificationDto) {
    return this.appStore.handleNotification(body.signedPayload);
  }
}
