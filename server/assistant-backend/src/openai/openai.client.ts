import { BadGatewayException, Injectable, ServiceUnavailableException } from '@nestjs/common';
import { config } from '../config';

/** The only place that talks to OpenAI. The key never leaves this process. */
@Injectable()
export class OpenAIClient {
  async post<T>(path: string, body: unknown): Promise<T> {
    const key = config.openAIKey;
    if (!key) throw new ServiceUnavailableException('The assistant is not configured.');
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), config.openAITimeoutMs);
    try {
      const response = await fetch(`${config.openAIBaseURL}${path}`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
      const text = await response.text();
      if (!response.ok) {
        // OpenAI's error text never includes the key; still, do not echo it to the app.
        throw new BadGatewayException(`OpenAI request failed (${response.status}).`);
      }
      return JSON.parse(text) as T;
    } catch (error) {
      if (error instanceof BadGatewayException) throw error;
      throw new BadGatewayException('OpenAI request failed.');
    } finally {
      clearTimeout(timer);
    }
  }
}
