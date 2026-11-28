import { NestExpressApplication } from '@nestjs/platform-express';
import { authed, FakeNetwork, makeApp, register, resetDatabase } from './helpers';

describe('realtime voice sessions', () => {
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

  async function fundedDevice() {
    const { token } = await register(app);
    const api = authed(app, token);
    await api.post('/api/grants/onboarding').send({ deviceCheckToken: `dc-${token.slice(-12)}` }).expect(200);
    return api;
  }

  it('refuses to start without credits', async () => {
    const { token } = await register(app);
    const res = await authed(app, token).post('/api/realtime/client-secret').send({ purpose: 'assistant' }).expect(402);
    expect(res.body.error).toBe('insufficient_credits');
    expect(net.openAICalls('/realtime/client_secrets')).toHaveLength(0);
  });

  it('mints a short-lived secret with server-fixed instructions and tools', async () => {
    const api = await fundedDevice();
    const res = await api
      .post('/api/realtime/client-secret')
      .send({ purpose: 'assistant', instructions: 'You are a general assistant. Write code.', tools: [{ name: 'run_shell' }] })
      .expect(200);
    expect(res.body.clientSecret).toMatch(/^ek_/);
    expect(res.body.model).toBe('gpt-realtime-2.1');

    const [call] = net.openAICalls('/realtime/client_secrets');
    expect(call.headers.Authorization).toBe('Bearer sk-test-not-a-real-key');
    const session = call.body.session;
    expect(session.model).toBe('gpt-realtime-2.1');
    expect(session.instructions).toContain('Ayurveda & Asana Yoga');
    expect(session.instructions).not.toContain('Write code');
    expect(session.tools.map((t: any) => t.name)).not.toContain('run_shell');
    expect(session.tools.map((t: any) => t.name)).toContain('log_food');
    expect(session.audio.input.turn_detection.type).toBe('semantic_vad');
    expect(call.body.expires_after.seconds).toBeLessThanOrEqual(7200);
    // The key never reaches the app.
    expect(JSON.stringify(res.body)).not.toContain('sk-test');
  });

  it('gives the constitution conversation only its own tools', async () => {
    const api = await fundedDevice();
    await api.post('/api/realtime/client-secret').send({ purpose: 'constitution' }).expect(200);
    const session = net.openAICalls('/realtime/client_secrets')[0].body.session;
    expect(session.tools.map((t: any) => t.name).sort()).toEqual(['create_meal_plan', 'get_profile', 'set_constitution']);
    expect(session.instructions).toContain('12 constitution questions');
  });

  it('meters reported usage once and charges a per-minute floor at the end', async () => {
    const api = await fundedDevice();
    const { body } = await api.post('/api/realtime/client-secret').send({ purpose: 'assistant' }).expect(200);
    // 10,000 audio-in tokens ($0.32) and 5,000 audio-out ($0.32): $0.64 = 64 credits at 100/USD,
    // more than the 60 granted, so the balance goes to zero and the app is told to stop.
    const usage = {
      input_tokens: 10_000,
      output_tokens: 5_000,
      input_token_details: { audio_tokens: 10_000, text_tokens: 0 },
      output_token_details: { audio_tokens: 5_000, text_tokens: 0 },
    };
    const small = { input_tokens: 1000, output_tokens: 100, input_token_details: { text_tokens: 1000 }, output_token_details: { text_tokens: 100 } };
    const r1 = await api.post(`/api/realtime/sessions/${body.sessionId}/usage`).send({ eventId: 'resp_a', kind: 'response', usage: small }).expect(200);
    expect(r1.body.insufficientCredits).toBe(false);
    const balanceAfterSmall = Number(r1.body.wallet.balanceMilli);
    expect(balanceAfterSmall).toBe(60_000 - 640); // $0.004 + $0.0024 = 0.64 credits

    // The same event again is not charged twice.
    const dup = await api.post(`/api/realtime/sessions/${body.sessionId}/usage`).send({ eventId: 'resp_a', kind: 'response', usage: small }).expect(200);
    expect(Number(dup.body.wallet.balanceMilli)).toBe(balanceAfterSmall);

    const big = await api.post(`/api/realtime/sessions/${body.sessionId}/usage`).send({ eventId: 'resp_b', kind: 'response', usage }).expect(200);
    expect(big.body.insufficientCredits).toBe(true);
    expect(big.body.wallet.credits).toBe(0);

    await api.post('/api/realtime/client-secret').send({ purpose: 'assistant' }).expect(402);
  });

  it('charges the floor when the app reports less than the minutes used', async () => {
    const api = await fundedDevice();
    const { body } = await api.post('/api/realtime/client-secret').send({ purpose: 'assistant' }).expect(200);
    const end = await api.post(`/api/realtime/sessions/${body.sessionId}/end`).expect(200);
    expect(end.body.minutes).toBe(1);
    expect(end.body.wallet.credits).toBe(57); // 60 - 3 credits for one started minute
    // Ending twice charges nothing more.
    const again = await api.post(`/api/realtime/sessions/${body.sessionId}/end`).expect(200);
    expect(again.body.wallet.credits).toBe(57);
  });
});
