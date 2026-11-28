import { readFileSync } from 'fs';
import { join } from 'path';

/**
 * Instructions and tools are fixed here, on the server, per purpose. The app
 * chooses a purpose; it can never send its own instructions or tools.
 */
export type AssistantPurpose = 'assistant' | 'constitution';
export type ReasoningPurpose = 'assistant' | 'plan' | 'photo';

const root = join(__dirname, '..', '..', 'assistant');

function read(name: string): string {
  return readFileSync(join(root, name), 'utf8').trim();
}

let cache: { instructions: string; constitution: string; photo: string; tools: ToolDefinition[] } | undefined;

export interface ToolDefinition {
  type: 'function';
  name: string;
  description: string;
  parameters: Record<string, unknown>;
}

function load() {
  if (!cache) {
    cache = {
      instructions: read('instructions.md'),
      constitution: read('constitution.md'),
      photo: read('photo.md'),
      tools: JSON.parse(readFileSync(join(root, 'tools.json'), 'utf8')) as ToolDefinition[],
    };
  }
  return cache;
}

export function allTools(): ToolDefinition[] {
  return load().tools;
}

const CONSTITUTION_TOOLS = new Set(['set_constitution', 'create_meal_plan', 'get_profile']);

export function realtimeInstructions(purpose: AssistantPurpose): string {
  const c = load();
  return purpose === 'constitution' ? `${c.instructions}\n\n${c.constitution}` : c.instructions;
}

export function realtimeTools(purpose: AssistantPurpose): ToolDefinition[] {
  const tools = load().tools;
  return purpose === 'constitution' ? tools.filter((t) => CONSTITUTION_TOOLS.has(t.name)) : tools;
}

export function reasoningInstructions(purpose: ReasoningPurpose): string {
  const c = load();
  if (purpose === 'photo') return `${c.instructions}\n\n${c.photo}`;
  if (purpose === 'plan') {
    return `${c.instructions}\n\nThe person wants a plan, a regimen or a recipe. Think it through, use get_profile and search_foods, then propose it with the create tools. Keep within every stored constraint and allergy.`;
  }
  return c.instructions;
}

/** Responses API function tools (strict JSON schema is not used: optional fields). */
export function reasoningTools(purpose: ReasoningPurpose): Array<ToolDefinition & { strict: false }> {
  const tools = purpose === 'photo' ? load().tools.filter((t) => t.name === 'set_dietary_constraints' || t.name === 'get_dietary_constraints') : load().tools;
  return tools.map((t) => ({ ...t, strict: false as const }));
}
