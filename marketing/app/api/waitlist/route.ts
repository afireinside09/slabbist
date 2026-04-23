import { createHash } from 'node:crypto';
import { NextResponse, type NextRequest } from 'next/server';
import { supabaseAdmin } from '@/lib/supabase-admin';

export const runtime = 'nodejs';

const AUDIENCES = new Set(['store', 'collector']);
const EMAIL_RE = /^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/;

// Rate limit: no more than RATE_LIMIT requests from the same IP per WINDOW_SECONDS.
const RATE_LIMIT = 3;
const WINDOW_SECONDS = 60;

function clientIp(req: NextRequest): string {
  const fwd = req.headers.get('x-forwarded-for');
  if (fwd) return fwd.split(',')[0].trim();
  return req.headers.get('x-real-ip') ?? 'unknown';
}

function hashIp(ip: string): string {
  const salt = process.env.WAITLIST_IP_SALT ?? '';
  return createHash('sha256').update(salt + '|' + ip).digest('hex');
}

async function notify(email: string, audience: string) {
  const webhook = process.env.WAITLIST_NOTIFY_WEBHOOK_URL;
  if (!webhook) return;
  try {
    await fetch(webhook, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        text: `New waitlist signup: *${email}* (${audience})`,
      }),
    });
  } catch (err) {
    // Never let a notification failure fail the signup.
    console.error('[waitlist] notify failed', err);
  }
}

type Body = { email?: unknown; audience?: unknown };

export async function POST(req: NextRequest) {
  let body: Body;
  try {
    body = (await req.json()) as Body;
  } catch {
    return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 });
  }

  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  const audience = typeof body.audience === 'string' ? body.audience : '';

  if (!EMAIL_RE.test(email)) {
    return NextResponse.json({ error: 'Invalid email' }, { status: 400 });
  }
  if (!AUDIENCES.has(audience)) {
    return NextResponse.json({ error: 'Invalid audience' }, { status: 400 });
  }

  const ip = clientIp(req);
  const ip_hash = hashIp(ip);

  const sb = supabaseAdmin();

  // Rate limit — count recent inserts from this IP hash.
  const sinceIso = new Date(Date.now() - WINDOW_SECONDS * 1000).toISOString();
  const { count, error: countErr } = await sb
    .from('waitlist')
    .select('id', { count: 'exact', head: true })
    .eq('ip_hash', ip_hash)
    .gte('created_at', sinceIso);

  if (countErr) {
    console.error('[waitlist] rate-limit query failed', countErr);
    return NextResponse.json({ error: 'Server error' }, { status: 500 });
  }
  if ((count ?? 0) >= RATE_LIMIT) {
    return NextResponse.json(
      { error: 'Too many requests — slow down and try again in a minute.' },
      { status: 429, headers: { 'Retry-After': String(WINDOW_SECONDS) } },
    );
  }

  const userAgent = req.headers.get('user-agent')?.slice(0, 400) ?? null;
  const source = req.headers.get('referer') ?? null;

  const { error } = await sb.from('waitlist').insert({
    email,
    audience,
    user_agent: userAgent,
    source,
    ip_hash,
  });

  // 23505 = unique_violation. Already on the list — treat as success.
  if (error && error.code !== '23505') {
    console.error('[waitlist] insert failed', error);
    return NextResponse.json({ error: 'Could not save. Try again?' }, { status: 500 });
  }

  // Only notify on truly new signups (not re-submits).
  if (!error) {
    // Fire-and-forget; don't await so the user isn't held up by a slow webhook.
    void notify(email, audience);
  }

  return NextResponse.json({ ok: true });
}
