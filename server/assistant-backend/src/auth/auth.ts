import {
  CanActivate,
  createParamDecorator,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  SetMetadata,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import type { Device } from '@prisma/client';
import { PrismaService } from '../prisma.service';

export const IS_PUBLIC = 'isPublic';
export const Public = () => SetMetadata(IS_PUBLIC, true);

export const CurrentDevice = createParamDecorator((_data: unknown, context: ExecutionContext): Device => {
  return context.switchToHttp().getRequest().device;
});

/** Every route needs the device token from /devices/register unless marked @Public. */
@Injectable()
export class DeviceAuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly jwt: JwtService,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, [context.getHandler(), context.getClass()])) return true;
    const request = context.switchToHttp().getRequest();
    const header = request.headers.authorization as string | undefined;
    const token = header?.startsWith('Bearer ') ? header.slice(7) : undefined;
    if (!token) throw new UnauthorizedException('Missing device token.');
    let payload: { sub: string };
    try {
      payload = await this.jwt.verifyAsync(token);
    } catch {
      throw new UnauthorizedException('Invalid or expired device token.');
    }
    const device = await this.prisma.device.findUnique({ where: { id: payload.sub } });
    if (!device) throw new UnauthorizedException('Unknown device.');
    if (device.blocked) throw new ForbiddenException('This device is blocked.');
    request.device = device;
    return true;
  }
}
