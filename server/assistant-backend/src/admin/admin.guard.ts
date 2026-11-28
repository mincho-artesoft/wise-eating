import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';
import { timingSafeEqual } from 'crypto';

/** Admin keys from ADMIN_API_KEYS (comma-separated, 32+ characters each), as LingoVela's X-Realtime-Admin-Key. */
export function adminKeys(): string[] {
  return (process.env.ADMIN_API_KEYS ?? '')
    .split(',')
    .map((k) => k.trim())
    .filter((k) => k.length >= 32);
}

@Injectable()
export class AdminGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const raw = request.headers['x-admin-key'];
    const given = Buffer.from(String(Array.isArray(raw) ? raw[0] : raw ?? ''));
    const ok = adminKeys().some((key) => {
      const k = Buffer.from(key);
      return k.length === given.length && timingSafeEqual(k, given);
    });
    if (!ok) throw new UnauthorizedException('Admin key required.');
    return true;
  }
}
