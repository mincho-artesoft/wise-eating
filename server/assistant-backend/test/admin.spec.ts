import { NestExpressApplication } from '@nestjs/platform-express';
import request from 'supertest';
import { ADMIN_KEY, authed, FakeNetwork, makeApp, register, resetDatabase } from './helpers';

describe('admin', () => {
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
  });

  const admin = (path: string) => request(app.getHttpServer()).get(`/api/admin${path}`).set('X-Admin-Key', ADMIN_KEY);

  it('refuses without the admin key, and a device token is not an admin key', async () => {
    const { token } = await register(app);
    await request(app.getHttpServer()).get('/api/admin/summary').expect(401);
    await request(app.getHttpServer()).get('/api/admin/summary').set('X-Admin-Key', 'wrong').expect(401);
    await request(app.getHttpServer()).get('/api/admin/summary').set('Authorization', `Bearer ${token}`).expect(401);
  });

  it('serves the page without data, and shows what happened', async () => {
    const page = await request(app.getHttpServer()).get('/api/admin').expect(200);
    expect(page.text).toContain('Ayurveda асистент');
    expect(page.headers['content-security-policy']).toContain("frame-ancestors 'none'");

    const { token } = await register(app);
    const api = authed(app, token);
    await api.post('/api/grants/onboarding').send({ deviceCheckToken: 'dc-admin' }).expect(200);
    const { body: secret } = await api.post('/api/realtime/client-secret').send({ purpose: 'assistant' }).expect(200);
    await api
      .post(`/api/realtime/sessions/${secret.sessionId}/usage`)
      .send({ eventId: 'r1', kind: 'response', usage: { input_tokens: 1000, output_tokens: 100, input_token_details: { text_tokens: 1000 }, output_token_details: { text_tokens: 100 } } })
      .expect(200);

    const { body: s } = await admin('/summary?days=7').expect(200);
    expect(s.totals.devices).toBe(1);
    expect(s.totals.activeSessions).toBe(1);
    expect(s.totals.grantsTotal).toBe(1);
    expect(s.totals.costUSD).toBeCloseTo(0.0064, 6);
    expect(s.settings.realtimeModel).toBe('gpt-realtime-2.1');
    expect(JSON.stringify(s)).not.toContain('sk-test');

    const { body: list } = await admin('/devices').expect(200);
    expect(list.devices[0].welcomeCredits).toBe(true);
    const id = list.devices[0].id;
    const { body: detail } = await admin(`/devices/${id}`).expect(200);
    expect(detail.ledger.map((l: any) => l.source)).toEqual(expect.arrayContaining(['ONBOARDING_GRANT', 'USAGE']));
  });

  it('adjusts credits with a reason and blocks a device', async () => {
    const { token } = await register(app);
    const { body: list } = await admin('/devices').expect(200);
    const id = list.devices[0].id;
    const post = (path: string, body: object) => request(app.getHttpServer()).post(`/api/admin${path}`).set('X-Admin-Key', ADMIN_KEY).send(body);
    await post(`/devices/${id}/credits`, { credits: 25 }).expect(400);
    expect((await post(`/devices/${id}/credits`, { credits: 25, reason: 'support' }).expect(200)).body.credits).toBe(25);
    expect((await post(`/devices/${id}/credits`, { credits: -5, reason: 'correction' }).expect(200)).body.credits).toBe(20);
    await post(`/devices/${id}/block`, { blocked: true }).expect(200);
    await authed(app, token).get('/api/wallet').expect(403);
  });
});
