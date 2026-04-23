// tests/_helpers/fake-supabase.ts
// Minimal Supabase-like adapter over pg-mem for ingest tests.
import { newDb, DataType } from "pg-mem";
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

export function makeFakeSupabase() {
  const db = newDb({ autoCreateForeignKeyIndices: true });
  db.public.registerFunction({
    name: "gen_random_uuid",
    returns: DataType.uuid,
    implementation: () => crypto.randomUUID(),
  });
  const mig = readFileSync(
    join(dirname(fileURLToPath(import.meta.url)), "../../..", "supabase/migrations/20260422120000_tcgcsv_pokemon_and_graded.sql"),
    "utf8",
  );
  // Strip the DO $$ ... $$ block (pg-mem lacks procedural language support).
  // RLS doesn't affect test semantics.
  const sqlNoRls = mig.replace(/do \$\$[\s\S]*?\$\$;?/gmi, "");
  db.public.none(sqlNoRls);

  const pg = db.adapters.createPg();
  const pool = new pg.Pool();

  return {
    from: (table: string) => ({
      upsert: async (rows: Record<string, unknown>[], { onConflict }: { onConflict: string }) => {
        const client = await pool.connect();
        try {
          for (const row of rows) {
            const cols = Object.keys(row);
            const vals = cols.map((_, i) => `$${i + 1}`);
            const params = cols.map((c) => row[c]);
            const conflictCols = onConflict.split(",").map((c) => c.trim());
            const updateSet = cols
              .filter((c) => !conflictCols.includes(c))
              .map((c) => `${c}=excluded.${c}`).join(",");
            const doUpdate = updateSet ? `do update set ${updateSet}` : `do nothing`;
            const sql = `insert into public.${table} (${cols.join(",")}) values (${vals.join(",")}) on conflict (${conflictCols.join(",")}) ${doUpdate}`;
            await client.query(sql, params);
          }
          return { error: null };
        } finally { client.release(); }
      },
      insert: async (rows: Record<string, unknown> | Record<string, unknown>[]) => {
        const arr = Array.isArray(rows) ? rows : [rows];
        const client = await pool.connect();
        try {
          for (const row of arr) {
            const cols = Object.keys(row);
            const vals = cols.map((_, i) => `$${i + 1}`);
            await client.query(
              `insert into public.${table} (${cols.join(",")}) values (${vals.join(",")})`,
              cols.map((c) => row[c]),
            );
          }
          return { error: null };
        } finally { client.release(); }
      },
      update: (patch: Record<string, unknown>) => ({
        eq: async (col: string, val: unknown) => {
          const client = await pool.connect();
          try {
            const setCols = Object.keys(patch);
            const setClause = setCols.map((c, i) => `${c}=$${i + 1}`).join(",");
            await client.query(
              `update public.${table} set ${setClause} where ${col} = $${setCols.length + 1}`,
              [...setCols.map((c) => patch[c]), val],
            );
            return { error: null };
          } finally { client.release(); }
        },
      }),
      select: (_cols?: string) => ({
        eq: async (col: string, val: unknown) => {
          const client = await pool.connect();
          try {
            const res = await client.query(
              `select * from public.${table} where ${col} = $1`,
              [val],
            );
            return { data: res.rows, error: null };
          } finally { client.release(); }
        },
      }),
    }),
    _debug: { pool, db },
  };
}
