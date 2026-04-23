import type { PokemonExtract, TcgExtendedField } from "@/raw/models.js";

const NUMBER_KEYS = new Set(["number", "cardnumber"]);
const RARITY_KEYS = new Set(["rarity"]);
const CARDTYPE_KEYS = new Set(["cardtype", "type"]);
const HP_KEYS = new Set(["hp"]);
const STAGE_KEYS = new Set(["stage"]);

const norm = (s: string) => s.toLowerCase().replace(/\s+/g, "");

function find(fields: readonly TcgExtendedField[], keys: Set<string>): string | null {
  for (const f of fields) {
    if (keys.has(norm(f.name)) || keys.has(norm(f.displayName))) return f.value;
  }
  return null;
}

export function extractPokemonFields(fields: readonly TcgExtendedField[]): PokemonExtract {
  return {
    cardNumber: find(fields, NUMBER_KEYS),
    rarity: find(fields, RARITY_KEYS),
    cardType: find(fields, CARDTYPE_KEYS),
    hp: find(fields, HP_KEYS),
    stage: find(fields, STAGE_KEYS),
  };
}
