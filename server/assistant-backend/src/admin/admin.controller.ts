import { Body, Controller, Get, Header, HttpCode, Param, Post, Query, UseGuards } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { readFileSync } from 'fs';
import { join } from 'path';
import { Public } from '../auth/auth';
import { AdminGuard } from './admin.guard';
import { AdminService } from './admin.service';

@Public()
@UseGuards(AdminGuard)
@Throttle({ default: { limit: 60, ttl: 60_000 } })
@Controller('admin')
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Get('summary')
  summary(@Query() query: Record<string, string>) {
    return this.admin.summary(query);
  }

  @Get('devices')
  devices(@Query() query: Record<string, string>) {
    return this.admin.devices(query);
  }

  @Get('devices/:id')
  device(@Param('id') id: string) {
    return this.admin.device(id);
  }

  @Post('devices/:id/credits')
  @HttpCode(200)
  adjust(@Param('id') id: string, @Body() body: Record<string, unknown>) {
    return this.admin.adjustCredits(id, body);
  }

  @Post('devices/:id/block')
  @HttpCode(200)
  block(@Param('id') id: string, @Body() body: { blocked?: unknown }) {
    return this.admin.setBlocked(id, body.blocked);
  }
}

let page: string | undefined;

/** The admin page itself (no data in it; it asks for the key and calls /api/admin). */
@Public()
@Throttle({ default: { limit: 30, ttl: 60_000 } })
@Controller('admin')
export class AdminPageController {
  @Get()
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Header('Cache-Control', 'no-store')
  @Header('X-Robots-Tag', 'noindex, nofollow')
  @Header('Content-Security-Policy', "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'")
  page() {
    page ??= readFileSync(join(__dirname, '..', '..', 'assistant', 'admin.html'), 'utf8');
    return page;
  }
}
