import { NestExpressApplication } from '@nestjs/platform-express';
import { Test } from '@nestjs/testing';
import { generateKeyPairSync, randomUUID } from 'crypto';
import request from 'supertest';

export const TEAM_ID = 'TEAMID1234';
export const BUNDLE_ID = 'com.example.ayura';

const deviceCheckKey = generateKeyPairSync('ec', { namedCurve: 'P-256' }).privateKey.export({ format: 'pem', type: 'pkcs8' }).toString();

export function baseEnv() {
  process.env.NODE_ENV = 'test';
  process.env.JWT_SECRET = 'test-secret-test-secret-test-secret-123';
  process.env.OPENAI_API_KEY = 'sk-test-not-a-real-key';
  process.env.APPLE_TEAM_ID = TEAM_ID;
  process.env.APPLE_BUNDLE_ID = BUNDLE_ID;
  process.env.APPLE_DEVICECHECK_KEY_ID = 'DCKEY12345';
  process.env.APPLE_DEVICECHECK_PRIVATE_KEY = deviceCheckKey;
  process.env.APP_ATTEST_REQUIRED = 'false';
  process.env.DEVICECHECK_REQUIRED = 'false';
  process.env.ALLOW_UNVERIFIED_STOREKIT_JWS = 'true';
  process.env.CREDITS_PER_USD = '100';
  process.env.ONBOARDING_GRANT_CREDITS = '60';
  process.env.THROTTLE_DISABLED = 'true';
}

export interface FetchCall {
  url: string;
  body: any;
  headers: Record<string, string>;
}

/**
 * Replaces global fetch: OpenAI and DeviceCheck answer from here; nothing
 * leaves the machine. DeviceCheck keeps two bits per device token.
 */
export class FakeNetwork {
  calls: FetchCall[] = [];
  bits = new Map<string, { bit0: boolean; bit1: boolean }>();
  responsesReply: any = {
    id: 'resp_1',
    output: [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Here is your plan.' }] }],
    usage: { input_tokens: 2000, output_tokens: 1000, input_tokens_details: { cached_tokens: 0 } },
  };

  install() {
    const original = global.fetch;
    global.fetch = (async (input: any, init?: any) => {
      const url = String(input);
      const body = init?.body ? JSON.parse(init.body) : undefined;
      this.calls.push({ url, body, headers: init?.headers ?? {} });
      if (url.endsWith('/realtime/client_secrets')) {
        return json({ value: `ek_${randomUUID()}`, expires_at: Math.floor(Date.now() / 1000) + 120, session: { id: 'sess_1' } });
      }
      if (url.endsWith('/responses')) return json(this.responsesReply);
      if (url.endsWith('/query_two_bits')) {
        const b = this.bits.get(body.device_token);
        return b ? json({ ...b, last_update_time: '2026-11' }) : new Response('Failed to find bit state', { status: 200 });
      }
      if (url.endsWith('/update_two_bits')) {
        this.bits.set(body.device_token, { bit0: body.bit0, bit1: body.bit1 });
        return new Response('', { status: 200 });
      }
      return new Response('not found', { status: 404 });
    }) as typeof fetch;
    return () => {
      global.fetch = original;
    };
  }

  openAICalls(path: string) {
    return this.calls.filter((c) => c.url.endsWith(path));
  }
}

function json(value: unknown) {
  return new Response(JSON.stringify(value), { status: 200, headers: { 'Content-Type': 'application/json' } });
}

export async function makeApp() {
  baseEnv();
  // Imported after the environment is set.
  const { AppModule } = await import('../src/app.module');
  const { configureApp } = await import('../src/main');
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
  const app = configureApp(moduleRef.createNestApplication<NestExpressApplication>());
  await app.init();
  return { app, moduleRef };
}

export async function resetDatabase(app: NestExpressApplication) {
  const { PrismaService } = await import('../src/prisma.service');
  const prisma = app.get(PrismaService);
  await prisma.$executeRawUnsafe(
    'TRUNCATE "CreditLedgerEntry","UsageEvent","RealtimeSession","AppStoreTransaction","OnboardingGrant","Device" CASCADE',
  );
  return prisma;
}

export async function register(app: NestExpressApplication, installId = randomUUID()) {
  const res = await request(app.getHttpServer()).post('/api/devices/register').send({ installId }).expect(200);
  return { token: res.body.token as string, installId, body: res.body };
}

export function authed(app: NestExpressApplication, token: string) {
  const server = app.getHttpServer();
  return {
    get: (path: string) => request(server).get(path).set('Authorization', `Bearer ${token}`),
    post: (path: string) => request(server).post(path).set('Authorization', `Bearer ${token}`),
  };
}
