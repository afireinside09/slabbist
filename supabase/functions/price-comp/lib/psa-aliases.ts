// supabase/functions/price-comp/lib/psa-aliases.ts
// AUTO-GENERATED from docs/data/psa-tcggroup-aliases.csv. Do not edit by hand;
// regenerate with `deno run --allow-read --allow-write /tmp/build-psa-aliases-ts.ts`.
// @ts-nocheck — Deno runtime; LSP can't resolve .ts paths.

export interface PsaAlias {
  /** TCGPlayer set group_id from tcg_groups */
  groupId: number;
  /** TCGPlayer abbreviation, useful for logging */
  abbreviation: string | null;
  /** TCGPlayer set's published year */
  publishedYear: number | null;
  /** Match confidence rating from the auto-matcher (high/medium/low). Surfaced for telemetry only — not load-bearing for runtime decisions. */
  confidence: "high" | "medium" | "low" | "none";
}

const aliases: Record<string, PsaAlias> = {
  "Aquapolis": { groupId: 1397, abbreviation: "AQ", publishedYear: 2003, confidence: "high" },
  "Bandai Carddass": { groupId: 23721, abbreviation: null, publishedYear: 1996, confidence: "medium" },
  "Base Set": { groupId: 604, abbreviation: "BS", publishedYear: 1999, confidence: "medium" },
  "Battle Partners Box Purchase Campaign": { groupId: 24174, abbreviation: "SVN", publishedYear: 2025, confidence: "medium" },
  "Black Bolt / White Flare": { groupId: 24325, abbreviation: "BLK", publishedYear: 2025, confidence: "medium" },
  "Brilliant Stars": { groupId: 2948, abbreviation: "SWSH09", publishedYear: 2022, confidence: "medium" },
  "Burning Shadows": { groupId: 1957, abbreviation: "SM03", publishedYear: 2017, confidence: "high" },
  "Celebrations": { groupId: 2867, abbreviation: "CLB", publishedYear: 2021, confidence: "medium" },
  "Champion's Path": { groupId: 2685, abbreviation: "CHP", publishedYear: 2020, confidence: "high" },
  "Champion's Path ETB Promo": { groupId: 2685, abbreviation: "CHP", publishedYear: 2020, confidence: "high" },
  "CoroCoro Comic Promo": { groupId: 23835, abbreviation: "sN", publishedYear: 2022, confidence: "medium" },
  "Cosmic Eclipse": { groupId: 2534, abbreviation: "SM12", publishedYear: 2019, confidence: "high" },
  "Crown Zenith": { groupId: 17688, abbreviation: "CRZ", publishedYear: 2023, confidence: "medium" },
  "Destined Rivals": { groupId: 24269, abbreviation: "DRI", publishedYear: 2025, confidence: "high" },
  "Dragons Exalted": { groupId: 1394, abbreviation: "DRX", publishedYear: 2012, confidence: "high" },
  "Evolving Skies": { groupId: 2848, abbreviation: "SWSH07", publishedYear: 2021, confidence: "high" },
  "EX Crystal Guardians": { groupId: 1395, abbreviation: "CG", publishedYear: 2006, confidence: "high" },
  "EX Deoxys": { groupId: 1375, abbreviation: "EX", publishedYear: 2002, confidence: "medium" },
  "EX Dragon Frontiers": { groupId: 1411, abbreviation: "DF", publishedYear: 2006, confidence: "high" },
  "EX Holon Phantoms": { groupId: 1379, abbreviation: "HP", publishedYear: 2006, confidence: "high" },
  "EX Power Keepers": { groupId: 1383, abbreviation: "PK", publishedYear: 2007, confidence: "high" },
  "EX Team Rocket Returns": { groupId: 1428, abbreviation: "RR", publishedYear: 2004, confidence: "high" },
  "EX Unseen Forces": { groupId: 1398, abbreviation: "UF", publishedYear: 2005, confidence: "high" },
  "Fossil": { groupId: 630, abbreviation: "FO", publishedYear: 1999, confidence: "high" },
  "Fusion Strike": { groupId: 2906, abbreviation: "SWSH08", publishedYear: 2021, confidence: "high" },
  "Generations": { groupId: 1728, abbreviation: "GEN", publishedYear: 2016, confidence: "medium" },
  "Hidden Fates": { groupId: 2480, abbreviation: "HIF", publishedYear: 2019, confidence: "medium" },
  "Hidden Fates ETB Promo": { groupId: 2480, abbreviation: "HIF", publishedYear: 2019, confidence: "medium" },
  "Japanese Base Set": { groupId: 604, abbreviation: "BS", publishedYear: 1999, confidence: "medium" },
  "Journey Together": { groupId: 24073, abbreviation: "JTG", publishedYear: 2025, confidence: "high" },
  "Jungle": { groupId: 635, abbreviation: "JU", publishedYear: 1999, confidence: "high" },
  "Lost Origin": { groupId: 3118, abbreviation: "SWSH11", publishedYear: 2022, confidence: "medium" },
  "M-P Promo": { groupId: 24423, abbreviation: "M-P", publishedYear: 2025, confidence: "high" },
  "Mega Evolution": { groupId: 24380, abbreviation: "MEG", publishedYear: 2025, confidence: "medium" },
  "Neo Destiny": { groupId: 1444, abbreviation: "N4", publishedYear: 2002, confidence: "high" },
  "Neo Discovery": { groupId: 1434, abbreviation: "N2", publishedYear: 2001, confidence: "high" },
  "Neo Genesis": { groupId: 1396, abbreviation: "N1", publishedYear: 2000, confidence: "high" },
  "Neo Revelation": { groupId: 1389, abbreviation: "N3", publishedYear: 2001, confidence: "high" },
  "Next Destinies": { groupId: 1412, abbreviation: "NXD", publishedYear: 2012, confidence: "high" },
  "Obsidian Flames": { groupId: 23228, abbreviation: "OBF", publishedYear: 2023, confidence: "high" },
  "Paldea Evolved": { groupId: 23120, abbreviation: "PAL", publishedYear: 2023, confidence: "high" },
  "Paldean Fates": { groupId: 23353, abbreviation: "PAF", publishedYear: 2024, confidence: "high" },
  "Phantasmal Flames": { groupId: 24448, abbreviation: "PFL", publishedYear: 2025, confidence: "high" },
  "Play! Pokemon Promo": { groupId: 1378, abbreviation: "LM", publishedYear: 2006, confidence: "medium" },
  "POKEMON GO": { groupId: 3064, abbreviation: "PGO", publishedYear: 2022, confidence: "medium" },
  "POKEMON JAPANESE EXPANSION 20TH ANNIVERSARY": { groupId: 23982, abbreviation: "CP6", publishedYear: 2016, confidence: "high" },
  "POKEMON PFL EN-PHANTASMAL FLAMES": { groupId: 24448, abbreviation: "PFL", publishedYear: 2025, confidence: "high" },
  "Pokemon Snap Promo": { groupId: 604, abbreviation: "BS", publishedYear: 1999, confidence: "medium" },
  "POKEMON SUN & MOON GUARDIANS RISING": { groupId: 1919, abbreviation: "SM02", publishedYear: 2017, confidence: "medium" },
  "Pokemon the Movie 2000 Promo": { groupId: 605, abbreviation: "BS2", publishedYear: 2000, confidence: "medium" },
  "POP Series 5": { groupId: 1414, abbreviation: "POP", publishedYear: 2026, confidence: "medium" },
  "Prismatic Evolutions": { groupId: 23821, abbreviation: "PRE", publishedYear: 2025, confidence: "high" },
  "Prismatic Evolutions ETB Promo": { groupId: 23821, abbreviation: "PRE", publishedYear: 2025, confidence: "high" },
  "Scarlet & Violet 151": { groupId: 23237, abbreviation: "MEW", publishedYear: 2023, confidence: "medium" },
  "Shining Fates": { groupId: 2754, abbreviation: "SHF", publishedYear: 2021, confidence: "medium" },
  "Silver Tempest": { groupId: 3170, abbreviation: "SWSH12", publishedYear: 2022, confidence: "medium" },
  "Skyridge": { groupId: 1372, abbreviation: "SK", publishedYear: 2003, confidence: "high" },
  "Southern Islands": { groupId: 648, abbreviation: "SI", publishedYear: 2001, confidence: "high" },
  "Stellar Crown": { groupId: 23537, abbreviation: "SCR", publishedYear: 2024, confidence: "high" },
  "Surging Sparks": { groupId: 23651, abbreviation: "SSP", publishedYear: 2024, confidence: "high" },
  "SV-P Promo": { groupId: 22872, abbreviation: "SVP", publishedYear: 2023, confidence: "medium" },
  "SVP Black Star Promo (Van Gogh Museum)": { groupId: 22872, abbreviation: "SVP", publishedYear: 2023, confidence: "medium" },
  "SWSH Black Star Promo": { groupId: 2585, abbreviation: "SWSH01", publishedYear: 2020, confidence: "medium" },
  "Team Rocket": { groupId: 1373, abbreviation: "TR", publishedYear: 2000, confidence: "high" },
  "Team Up": { groupId: 2377, abbreviation: "SM9", publishedYear: 2019, confidence: "high" },
  "Terastal Festival ex": { groupId: 23909, abbreviation: "SV8a", publishedYear: 2024, confidence: "medium" },
  "Topps Chrome Series 1": { groupId: 605, abbreviation: "BS2", publishedYear: 2000, confidence: "medium" },
  "Triplet Beat": { groupId: 23598, abbreviation: "SV1a", publishedYear: 2023, confidence: "high" },
  "Trophy": { groupId: 604, abbreviation: "BS", publishedYear: 1999, confidence: "medium" },
  "Twilight Masquerade": { groupId: 23473, abbreviation: "TWM", publishedYear: 2024, confidence: "high" },
  "Ultra Prism": { groupId: 2178, abbreviation: "SM05", publishedYear: 2018, confidence: "high" },
  "Unified Minds": { groupId: 2464, abbreviation: "SM11", publishedYear: 2019, confidence: "high" },
  "Vivid Voltage": { groupId: 2701, abbreviation: "SWSH04", publishedYear: 2020, confidence: "high" },
  "VS Series": { groupId: 24180, abbreviation: null, publishedYear: 2001, confidence: "medium" },
  "World Championships Promo": { groupId: 24205, abbreviation: null, publishedYear: 2026, confidence: "medium" },
  "XY Black Star Promo": { groupId: 23887, abbreviation: "XY", publishedYear: 2017, confidence: "medium" },
  "XY Evolutions": { groupId: 23887, abbreviation: "XY", publishedYear: 2017, confidence: "medium" },
  "XY Promo": { groupId: 1387, abbreviation: "XY", publishedYear: 2014, confidence: "high" },
};

/**
 * Look up a curated PSA set name → tcg_groups bridge entry.
 * Returns null if the PSA set isn't in our alias table or has no tcg_group_id.
 * Match is exact (case-sensitive) on the psa_set_name as it appears in graded_card_identities.
 */
export function aliasForPsaSet(psaSetName: string): PsaAlias | null {
  return aliases[psaSetName] ?? null;
}
