// @ts-nocheck — this file runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports; runtime is correct.
const ANTHROPIC_URL = 'https://api.anthropic.com/v1/messages';
const API_VERSION = '2023-06-01';

export type ContentBlock =
  | { type: 'text'; text: string }
  | { type: 'image'; source: { type: 'base64'; media_type: 'image/jpeg' | 'image/png'; data: string } };

export interface MessagesRequest {
  model: string;
  max_tokens: number;
  system: string;
  messages: Array<{ role: 'user' | 'assistant'; content: ContentBlock[] }>;
}

export interface MessagesResponse {
  id: string;
  content: Array<{ type: 'text'; text: string }>;
  stop_reason: string;
  model: string;
}

export async function callMessages(
  body: MessagesRequest,
  opts: { timeoutMs?: number } = {},
): Promise<MessagesResponse> {
  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) throw new Error('ANTHROPIC_API_KEY not set');

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeoutMs ?? 18_000);

  try {
    const res = await fetch(ANTHROPIC_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': API_VERSION,
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`anthropic ${res.status}: ${text}`);
    }
    return await res.json() as MessagesResponse;
  } finally {
    clearTimeout(timer);
  }
}
