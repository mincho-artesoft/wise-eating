import { NestExpressApplication } from '@nestjs/platform-express';
import { randomUUID } from 'crypto';
import request from 'supertest';
import { authed, BUNDLE_ID, FakeNetwork, makeApp, register, resetDatabase } from './helpers';

function unsignedJWS(payload: object) {
  const part = (o: object) => Buffer.from(JSON.stringify(o)).toString('base64url');
  return `${part({ alg: 'ES256' })}.${part(payload)}.sig`;
}

describe('App Store credits', () => {
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

  it('grants a pack once per transaction and takes it back on refund', async () => {
    const { token, body } = await register(app);
    const api = authed(app, token);
    const transactionId = randomUUID();
    const tx = {
      transactionId,
      originalTransactionId: transactionId,
      productId: 'com.ayurveda.asanayoga.credits.small',
      bundleId: BUNDLE_ID,
      appAccountToken: body.appAccountToken,
      environment: 'Sandbox',
      purchaseDate: Date.now(),
    };
    const first = await api.post('/api/app-store/transactions').send({ signedTransactionInfo: unsignedJWS(tx) }).expect(200);
    expect(first.body.granted).toBe(300);
    const again = await api.post('/api/app-store/transactions').send({ signedTransactionInfo: unsignedJWS(tx) }).expect(200);
    expect(again.body.granted).toBe(0);
    expect(again.body.wallet.credits).toBe(300);

    await request(app.getHttpServer())
      .post('/api/app-store/notifications')
      .send({ signedPayload: unsignedJWS({ notificationType: 'REFUND', data: { environment: 'Sandbox', signedTransactionInfo: unsignedJWS({ ...tx, revocationDate: Date.now() }) } }) })
      .expect(200);
    const wallet = await api.get('/api/wallet').expect(200);
    expect(wallet.body.wallet.credits).toBe(0);
  });

  it('grants each subscription period and refuses another app', async () => {
    const { token, body } = await register(app);
    const api = authed(app, token);
    const original = randomUUID();
    for (const id of [original, randomUUID()]) {
      const tx = { transactionId: id, originalTransactionId: original, productId: 'com.ayurveda.asanayoga.assistant.monthly', bundleId: BUNDLE_ID, appAccountToken: body.appAccountToken, environment: 'Sandbox' };
      await request(app.getHttpServer())
        .post('/api/app-store/notifications')
        .send({ signedPayload: unsignedJWS({ notificationType: 'DID_RENEW', data: { environment: 'Sandbox', signedTransactionInfo: unsignedJWS(tx) } }) })
        .expect(200);
    }
    expect((await api.get('/api/wallet')).body.wallet.credits).toBe(1000);

    const foreign = { transactionId: randomUUID(), productId: 'com.ayurveda.asanayoga.credits.large', bundleId: 'com.other.app', environment: 'Sandbox' };
    await api.post('/api/app-store/transactions').send({ signedTransactionInfo: unsignedJWS(foreign) }).expect(403);
  });
});
