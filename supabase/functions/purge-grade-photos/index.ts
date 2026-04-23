import { serviceRoleClient } from '../_shared/supabase.ts';

const BATCH_SIZE = 500;
const PURGE_AFTER_DAYS = 30;
const PURGE_SECRET_HEADER = 'x-purge-secret';

Deno.serve(async (req) => {
  // Simple shared-secret guard so only the cron schedule can invoke this.
  const secret = req.headers.get(PURGE_SECRET_HEADER);
  if (secret !== Deno.env.get('PURGE_GRADE_PHOTOS_SECRET')) {
    return new Response('forbidden', { status: 403 });
  }

  const client = serviceRoleClient();
  const cutoff = new Date(Date.now() - PURGE_AFTER_DAYS * 24 * 60 * 60 * 1000).toISOString();

  const { data: rows, error } = await client
    .from('grade_estimates')
    .select('id, front_image_path, back_image_path')
    .is('images_purged_at', null)
    .lt('created_at', cutoff)
    .limit(BATCH_SIZE);

  if (error) {
    console.error('purge: list failed', error);
    return new Response(JSON.stringify({ error: 'list_failed' }), { status: 500 });
  }
  if (!rows || rows.length === 0) {
    return new Response(JSON.stringify({ purged: 0 }), { status: 200 });
  }

  const paths = rows.flatMap((r) => [r.front_image_path, r.back_image_path]);
  const { error: removeErr } = await client.storage.from('grade-photos').remove(paths);
  if (removeErr) {
    console.error('purge: remove failed', removeErr);
    return new Response(JSON.stringify({ error: 'remove_failed' }), { status: 500 });
  }

  const ids = rows.map((r) => r.id);
  const { error: updateErr } = await client
    .from('grade_estimates')
    .update({ images_purged_at: new Date().toISOString() })
    .in('id', ids);
  if (updateErr) {
    console.error('purge: mark failed', updateErr);
    return new Response(JSON.stringify({ error: 'mark_failed' }), { status: 500 });
  }

  return new Response(JSON.stringify({ purged: ids.length }), { status: 200 });
});
