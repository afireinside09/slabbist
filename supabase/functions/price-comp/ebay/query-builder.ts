// @ts-nocheck — runs on Deno. Local TS LSP can't resolve `std/*` imports or `.ts` relative paths that Deno accepts.

import type { GradedCardIdentity, GradingService } from "../types.ts";
import { normalizeCardName } from "../lib/card-name-normalize.ts";

export interface CascadeQuery {
  shape: "narrow" | "broad";
  windowDays: 90 | 365;
  q: string;
  categoryId: "183454";
}

const POKEMON_CATEGORY = "183454";

function narrow(id: GradedCardIdentity, svc: GradingService, grade: string): string {
  const name = normalizeCardName(id.card_name);
  const phrase = id.card_number ? `${name} ${id.card_number}` : name;
  return `"${phrase}" "${svc} ${grade}"`;
}

function broad(id: GradedCardIdentity, svc: GradingService, grade: string): string {
  const name = normalizeCardName(id.card_name);
  const parts = [name, id.set_name, id.card_number, `${svc} ${grade}`]
    .filter((p): p is string => typeof p === "string" && p.length > 0);
  return parts.join(" ");
}

export function buildCascadeQueries(
  id: GradedCardIdentity,
  svc: GradingService,
  grade: string,
): CascadeQuery[] {
  return [
    { shape: "narrow", windowDays: 90,  q: narrow(id, svc, grade), categoryId: POKEMON_CATEGORY },
    { shape: "broad",  windowDays: 90,  q: broad(id, svc, grade),  categoryId: POKEMON_CATEGORY },
    { shape: "narrow", windowDays: 365, q: narrow(id, svc, grade), categoryId: POKEMON_CATEGORY },
    { shape: "broad",  windowDays: 365, q: broad(id, svc, grade),  categoryId: POKEMON_CATEGORY },
  ];
}
