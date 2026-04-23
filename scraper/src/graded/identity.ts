import type { SupabaseClient } from "@supabase/supabase-js";
import type { GradedCardIdentityInput } from "@/graded/models.js";

export interface NormalizedIdentityKey {
  game: "pokemon";
  language: "en" | "jp";
  setName: string;
  cardName: string;
  cardNumber: string;
  variant: string;
}

function normText(s: string | null | undefined): string {
  return (s ?? "")
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\/\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

export function normalizeIdentityKey(input: GradedCardIdentityInput): NormalizedIdentityKey {
  return {
    game: input.game,
    language: input.language,
    setName: normText(input.setName),
    cardName: normText(input.cardName),
    cardNumber: (input.cardNumber ?? "").trim(),
    variant: normText(input.variant ?? ""),
  };
}

export async function findOrCreateIdentity(
  supabase: SupabaseClient,
  input: GradedCardIdentityInput,
): Promise<string> {
  const key = normalizeIdentityKey(input);
  const { data } = await supabase
    .from("graded_card_identities")
    .select("id, set_name, card_name, card_number, variant, language")
    .eq("game", key.game);
  const list = (data ?? []) as Array<Record<string, unknown>>;
  for (const row of list) {
    const candidate = normalizeIdentityKey({
      game: "pokemon",
      language: row.language as "en" | "jp",
      setName: String(row.set_name ?? ""),
      cardName: String(row.card_name ?? ""),
      cardNumber: String(row.card_number ?? ""),
      variant: String(row.variant ?? ""),
    });
    if (
      candidate.language === key.language &&
      candidate.setName === key.setName &&
      candidate.cardName === key.cardName &&
      candidate.cardNumber === key.cardNumber &&
      candidate.variant === key.variant
    ) {
      return String(row.id);
    }
  }
  const id = crypto.randomUUID();
  await supabase.from("graded_card_identities").insert({
    id, game: input.game, language: input.language,
    set_name: input.setName, set_code: input.setCode ?? null, year: input.year ?? null,
    card_number: input.cardNumber ?? null, card_name: input.cardName,
    variant: input.variant ?? null,
  });
  return id;
}
