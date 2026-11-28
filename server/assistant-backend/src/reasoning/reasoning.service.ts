import { BadRequestException, Injectable } from '@nestjs/common';
import { Device, UsageKind } from '@prisma/client';
import { allTools, ReasoningPurpose, reasoningInstructions, reasoningTools } from '../assistant/assistant-config';
import { chargeMilliForCost, config } from '../config';
import { OpenAIClient } from '../openai/openai.client';
import { PrismaService } from '../prisma.service';
import { breakdown, costMicros, OpenAIUsage } from '../realtime/pricing';
import { InsufficientCreditsException, safetyIdentifier } from '../realtime/realtime.service';
import { WalletService } from '../wallet/wallet.service';

/** Conversation items the app may send back; anything else is refused. */
type InputItem =
  | { type?: 'message'; role: 'user' | 'assistant'; content: string | Array<{ type: string; text?: string }> }
  | { type: 'function_call'; call_id: string; name: string; arguments: string; id?: string }
  | { type: 'function_call_output'; call_id: string; output: string }
  | { type: 'reasoning'; id?: string; encrypted_content?: string; summary?: unknown[] };

interface ResponsesResult {
  id?: string;
  output?: Array<Record<string, unknown>>;
  usage?: OpenAIUsage;
}

const MAX_INPUT_CHARS = 120_000;
const MAX_IMAGE_BYTES = 6 * 1024 * 1024;

@Injectable()
export class ReasoningService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly wallet: WalletService,
    private readonly openai: OpenAIClient,
  ) {}

  validate(items: unknown[], toolNames: Set<string>): InputItem[] {
    if (!Array.isArray(items) || items.length === 0 || items.length > 80) throw new BadRequestException('input must have 1 to 80 items');
    if (JSON.stringify(items).length > MAX_INPUT_CHARS) throw new BadRequestException('input is too long');
    return items.map((raw) => {
      const item = raw as Record<string, unknown>;
      const type = (item.type as string | undefined) ?? 'message';
      if (type === 'message') {
        if (item.role !== 'user' && item.role !== 'assistant') throw new BadRequestException('only user and assistant messages');
        const content = item.content;
        if (typeof content === 'string') return { type: 'message', role: item.role, content } as InputItem;
        if (Array.isArray(content) && content.every((c) => ['input_text', 'output_text'].includes((c as { type: string }).type))) {
          return { type: 'message', role: item.role, content } as InputItem;
        }
        throw new BadRequestException('message content must be text');
      }
      if (type === 'function_call') {
        if (!toolNames.has(item.name as string)) throw new BadRequestException('unknown tool');
        return { type, call_id: String(item.call_id), name: String(item.name), arguments: String(item.arguments ?? '{}') };
      }
      if (type === 'function_call_output') {
        return { type, call_id: String(item.call_id), output: String(item.output ?? '').slice(0, 40_000) };
      }
      if (type === 'reasoning') {
        return { type, id: item.id as string | undefined, encrypted_content: item.encrypted_content as string | undefined, summary: (item.summary as unknown[]) ?? [] };
      }
      throw new BadRequestException(`item type ${type} is not allowed`);
    });
  }

  async respond(device: Device, body: { purpose: ReasoningPurpose; requestId: string; input: unknown[]; imageJPEGBase64?: string }) {
    const balance = await this.wallet.balanceMilli(device.id);
    if (balance < BigInt(Math.ceil(config.minCreditsToStart * 1000))) throw new InsufficientCreditsException(balance);

    const tools = reasoningTools(body.purpose);
    // Earlier turns may hold calls to any of the app's tools; new calls are limited by `tools`.
    const input: unknown[] = this.validate(body.input, new Set(allTools().map((t) => t.name)));
    if (body.imageJPEGBase64) {
      if (body.purpose !== 'photo') throw new BadRequestException('images are only accepted for photo requests');
      const bytes = Buffer.from(body.imageJPEGBase64, 'base64');
      if (bytes.length === 0 || bytes.length > MAX_IMAGE_BYTES || bytes[0] !== 0xff || bytes[1] !== 0xd8) {
        throw new BadRequestException('image must be a JPEG under 6 MB');
      }
      // The image goes to OpenAI in this request only; it is not stored here.
      input.push({
        type: 'message',
        role: 'user',
        content: [
          { type: 'input_text', text: 'The photo the person chose to send.' },
          { type: 'input_image', image_url: `data:image/jpeg;base64,${body.imageJPEGBase64}`, detail: 'high' },
        ],
      });
    }

    const result = await this.openai.post<ResponsesResult>('/responses', {
      model: config.reasoningModel,
      instructions: reasoningInstructions(body.purpose),
      input,
      tools,
      tool_choice: 'auto',
      parallel_tool_calls: true,
      store: false,
      include: ['reasoning.encrypted_content'],
      max_output_tokens: 4000,
      safety_identifier: safetyIdentifier(device.id),
    });

    const usage = result.usage ?? {};
    const cost = costMicros(config.reasoningModel, usage);
    const key = `reasoning:${device.id}:${body.requestId}`;
    const t = breakdown(usage);
    const charged = await this.wallet.serializable(async (tx) => {
      const existing = await tx.usageEvent.findUnique({ where: { idempotencyKey: key } });
      if (existing) return existing.chargedMilli;
      const debit = await this.wallet.debit(device.id, chargeMilliForCost(cost), key, { purpose: body.purpose }, tx);
      await tx.usageEvent.create({
        data: {
          deviceId: device.id,
          kind: UsageKind.REASONING,
          model: config.reasoningModel,
          purpose: body.purpose,
          inputTextTokens: t.textIn,
          inputImageTokens: t.imageIn,
          cachedInputTokens: t.cachedText,
          outputTextTokens: t.textOut,
          costMicrosUSD: cost,
          chargedMilli: debit.chargedMilli,
          idempotencyKey: key,
        },
      });
      return debit.chargedMilli;
    });

    const output = (result.output ?? []).filter((o) => ['message', 'function_call', 'reasoning'].includes(o.type as string));
    const text = output
      .filter((o) => o.type === 'message')
      .flatMap((o) => (o.content as Array<{ type: string; text?: string }> | undefined) ?? [])
      .filter((c) => c.type === 'output_text')
      .map((c) => c.text ?? '')
      .join('\n')
      .trim();
    return { output, text, chargedMilli: charged.toString(), wallet: await this.wallet.view(device.id) };
  }
}
