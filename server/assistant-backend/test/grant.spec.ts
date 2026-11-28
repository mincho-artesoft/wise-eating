import { NestExpressApplication } from '@nestjs/platform-express';
import { randomUUID } from 'crypto';
import { authed, FakeNetwork, makeApp, register, resetDatabase } from './helpers';

describe('devices and the onboarding grant', () => {
  let app: NestExpressApplication;
  const net = new FakeNetwork();
  let restore: () => void;

  beforeAll(async () => {
    restore = net.install();
    ({ app } = await makeApp());
  });
  afterAll(async () => {
    await app.close();
    restore();
  });
  beforeEach(async () => {
    await resetDatabase(app);
    net.calls = [];
    net.bits.clear();
  });

  it('registers an install and gives the welcome credits once', async () => {
    const { token, body } = await register(app);
    expect(body.wallet.credits).toBe(0);
    expect(body.onboardingGrant).toBe('available');
    const api = authed(app, token);

    const first = await api.post('/api/grants/onboarding').send({ deviceCheckToken: 'dc-token-A' }).expect(200);
    expect(first.body.granted).toBe(60);
    expect(first.body.wallet.credits).toBe(60);
    expect(net.bits.get('dc-token-A')).toEqual({ bit0: true, bit1: false });

    await api.post('/api/grants/onboarding').send({ deviceCheckToken: 'dc-token-A' }).expect(409);
    const wallet = await api.get('/api/wallet').expect(200);
    expect(wallet.body.wallet.credits).toBe(60);
    expect(wallet.body.onboardingGrant).toBe('used');
  });

  it('does not give the credits again after a reinstall', async () => {
    const installId = randomUUID();
    const a = await register(app, installId);
    await authed(app, a.token).post('/api/grants/onboarding').send({ deviceCheckToken: 'dc-token-B' }).expect(200);

    // Same keychain install id after reinstalling: our own records refuse.
    const again = await register(app, installId);
    expect(again.body.onboardingGrant).toBe('used');
    await authed(app, again.token).post('/api/grants/onboarding').send({ deviceCheckToken: 'dc-token-B' }).expect(409);

    // Keychain wiped (new install id) on the same phone: Apple's DeviceCheck bit refuses.
    const wiped = await register(app);
    expect(wiped.body.onboardingGrant).toBe('available');
    const res = await authed(app, wiped.token).post('/api/grants/onboarding').send({ deviceCheckToken: 'dc-token-B' }).expect(409);
    expect(res.body.message).toMatch(/already given on this device/);
  });

  it('requires DeviceCheck when configured to', async () => {
    process.env.DEVICECHECK_REQUIRED = 'true';
    try {
      const { token } = await register(app);
      await authed(app, token).post('/api/grants/onboarding').send({}).expect(403);
    } finally {
      process.env.DEVICECHECK_REQUIRED = 'false';
    }
  });

  it('refuses requests without a device token', async () => {
    const request = (await import('supertest')).default;
    await request(app.getHttpServer()).get('/api/wallet').expect(401);
    await request(app.getHttpServer()).post('/api/realtime/client-secret').send({ purpose: 'assistant' }).expect(401);
  });
});
