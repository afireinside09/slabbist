// @ts-nocheck — this file runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports; runtime is correct.
import { corsHeaders, handleOptions } from '../_shared/cors.ts';
import { serviceRoleClient, userClient } from '../_shared/supabase.ts';
import { callMessages, ContentBlock } from '../_shared/anthropic.ts';
import type { GradeEstimateRequest, GradeEstimateLLMOutput } from './types.ts';
import { SYSTEM_PROMPT, buildUserPrompt, validateOutput } from './prompt.ts';

const MODEL = 'claude-sonnet-4-6';
const MODEL_VERSION_TAG = 'claude-sonnet-4-6@2026-04-23-v1';
const DAILY_LIMIT = 20;

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'content-type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions();
  if (req.method !== 'POST') return jsonResponse(405, { error: 'method_not_allowed' });

  // 1. Auth
  const userScoped = userClient(req);
  const { data: userData, error: userErr } = await userScoped.auth.getUser();
  if (userErr || !userData.user) return jsonResponse(401, { error: 'unauthorized' });
  const userId = userData.user.id;

  // 2. Parse + validate request
  let body: GradeEstimateRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse(400, { error: 'invalid_json' });
  }
  if (!body.front_image_path || !body.back_image_path) {
    return jsonResponse(400, { error: 'missing_image_paths' });
  }
  if (!body.centering_front || !body.centering_back) {
    return jsonResponse(400, { error: 'missing_centering' });
  }

  // 3. Rate limit (daily count for user)
  const service = serviceRoleClient();
  const { count: dailyCount } = await service
    .from('grade_estimates')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .gte('created_at', new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString());
  if ((dailyCount ?? 0) >= DAILY_LIMIT) {
    return jsonResponse(429, { error: 'rate_limited', limit: DAILY_LIMIT });
  }

  // 4. Fetch images from storage as base64
  const [frontBytes, backBytes] = await Promise.all([
    downloadAsBase64(service, body.front_image_path),
    downloadAsBase64(service, body.back_image_path),
  ]);

  // 5. Build prompt + call Anthropic, with one retry on schema-validation failure
  const userPrompt = buildUserPrompt({
    centering_front: body.centering_front,
    centering_back: body.centering_back,
    include_other_graders: body.include_other_graders,
  });
  const content: ContentBlock[] = [
    { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: frontBytes } },
    { type: 'image', source: { type: 'base64', media_type: 'image/jpeg', data: backBytes } },
    { type: 'text', text: userPrompt },
  ];

  let parsed: GradeEstimateLLMOutput | null = null;
  let lastError: unknown = null;
  for (let attempt = 0; attempt < 2 && parsed === null; attempt++) {
    try {
      const res = await callMessages({
        model: MODEL,
        max_tokens: 1500,
        system: SYSTEM_PROMPT,
        messages: [{ role: 'user', content }],
      });
      const text = res.content.map((b) => b.text).join('');
      const jsonStart = text.indexOf('{');
      const jsonEnd = text.lastIndexOf('}');
      if (jsonStart < 0 || jsonEnd < 0) throw new Error('no JSON object in output');
      const candidate = JSON.parse(text.slice(jsonStart, jsonEnd + 1));
      parsed = validateOutput(candidate);
    } catch (e) {
      lastError = e;
    }
  }
  if (parsed === null) {
    console.error('grade-estimate: validation failed', lastError);
    return jsonResponse(502, { error: 'model_output_invalid' });
  }

  // 6. Derive thumbnail paths from image paths by convention.
  const frontThumb = body.front_image_path.replace(/\/front\.jpg$/, '/front_thumb.jpg');
  const backThumb = body.back_image_path.replace(/\/back\.jpg$/, '/back_thumb.jpg');

  // 7. Persist
  const { data: row, error: insertErr } = await service
    .from('grade_estimates')
    .insert({
      user_id: userId,
      scan_id: null,
      front_image_path: body.front_image_path,
      back_image_path: body.back_image_path,
      front_thumb_path: frontThumb,
      back_thumb_path: backThumb,
      centering_front: body.centering_front,
      centering_back: body.centering_back,
      sub_grades: parsed.sub_grades,
      sub_grade_notes: parsed.sub_grade_notes,
      composite_grade: parsed.composite_grade,
      confidence: parsed.confidence,
      verdict: parsed.verdict,
      verdict_reasoning: parsed.verdict_reasoning,
      other_graders: parsed.other_graders,
      model_version: MODEL_VERSION_TAG,
    })
    .select()
    .single();
  if (insertErr) {
    console.error('grade-estimate: insert failed', insertErr);
    return jsonResponse(500, { error: 'persist_failed' });
  }

  return jsonResponse(200, row);
});

async function downloadAsBase64(client: ReturnType<typeof serviceRoleClient>, path: string): Promise<string> {
  const { data, error } = await client.storage.from('grade-photos').download(path);
  if (error || !data) throw new Error(`download failed: ${path}`);
  const buf = await data.arrayBuffer();
  return base64Encode(new Uint8Array(buf));
}

function base64Encode(bytes: Uint8Array): string {
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}
