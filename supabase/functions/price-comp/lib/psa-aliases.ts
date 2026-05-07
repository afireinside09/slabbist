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
  /** Second-best group_id from CSV alt_2_id; tried as a fallback when the primary group has no tcg_products row. PSA set names commonly span both an English (e.g. SV: Scarlet & Violet Promo Cards) and a Japanese (e.g. SV-P Promotional Cards) TCGPlayer group. */
  altGroupId: number | null;
}

const aliases: Record<string, PsaAlias> = {
  "Aquapolis": { groupId: 1397, abbreviation: "AQ", publishedYear: 2003, confidence: "high", altGroupId: 1372 },
  "Bandai Carddass": { groupId: 23721, abbreviation: null, publishedYear: 1996, confidence: "medium", altGroupId: 23740 },
  "Base Set": { groupId: 604, abbreviation: "BS", publishedYear: 1999, confidence: "medium", altGroupId: 1663 },
  "Battle Partners Box Purchase Campaign": { groupId: 24174, abbreviation: "SVN", publishedYear: 2025, confidence: "medium", altGroupId: 24173 },
  "Black Bolt / White Flare": { groupId: 24325, abbreviation: "BLK", publishedYear: 2025, confidence: "medium", altGroupId: 24326 },
  "Brilliant Stars": { groupId: 2948, abbreviation: "SWSH09", publishedYear: 2022, confidence: "medium", altGroupId: 3020 },
  "Burning Shadows": { groupId: 1957, abbreviation: "SM03", publishedYear: 2017, confidence: "high", altGroupId: 1863 },
  "Celebrations": { groupId: 2867, abbreviation: "CLB", publishedYear: 2021, confidence: "medium", altGroupId: 2931 },
  "Champion's Path": { groupId: 2685, abbreviation: "CHP", publishedYear: 2020, confidence: "high", altGroupId: 2585 },
  "Champion's Path ETB Promo": { groupId: 2685, abbreviation: "CHP", publishedYear: 2020, confidence: "high", altGroupId: 2585 },
  "CoroCoro Comic Promo": { groupId: 23835, abbreviation: "sN", publishedYear: 2022, confidence: "medium", altGroupId: 23725 },
  "Cosmic Eclipse": { groupId: 2534, abbreviation: "SM12", publishedYear: 2019, confidence: "high", altGroupId: 2377 },
  "Crown Zenith": { groupId: 17688, abbreviation: "CRZ", publishedYear: 2023, confidence: "medium", altGroupId: 17689 },
  "Destined Rivals": { groupId: 24269, abbreviation: "DRI", publishedYear: 2025, confidence: "high", altGroupId: 23821 },
  "Dragons Exalted": { groupId: 1394, abbreviation: "DRX", publishedYear: 2012, confidence: "high", altGroupId: 1386 },
  "Evolving Skies": { groupId: 2848, abbreviation: "SWSH07", publishedYear: 2021, confidence: "high", altGroupId: 2754 },
  "EX Crystal Guardians": { groupId: 1395, abbreviation: "CG", publishedYear: 2006, confidence: "high", altGroupId: 1375 },
  "EX Deoxys": { groupId: 1375, abbreviation: "EX", publishedYear: 2002, confidence: "medium", altGroupId: 1404 },
  "EX Dragon Frontiers": { groupId: 1411, abbreviation: "DF", publishedYear: 2006, confidence: "high", altGroupId: 1375 },
  "EX Holon Phantoms": { groupId: 1379, abbreviation: "HP", publishedYear: 2006, confidence: "high", altGroupId: 1375 },
  "EX Power Keepers": { groupId: 1383, abbreviation: "PK", publishedYear: 2007, confidence: "high", altGroupId: 1375 },
  "EX Team Rocket Returns": { groupId: 1428, abbreviation: "RR", publishedYear: 2004, confidence: "high", altGroupId: 1375 },
  "EX Unseen Forces": { groupId: 1398, abbreviation: "UF", publishedYear: 2005, confidence: "high", altGroupId: 1375 },
  "Fossil": { groupId: 630, abbreviation: "FO", publishedYear: 1999, confidence: "high", altGroupId: 604 },
  "Fusion Strike": { groupId: 2906, abbreviation: "SWSH08", publishedYear: 2021, confidence: "high", altGroupId: 23627 },
  "Generations": { groupId: 1728, abbreviation: "GEN", publishedYear: 2016, confidence: "medium", altGroupId: 1729 },
  "Hidden Fates": { groupId: 2480, abbreviation: "HIF", publishedYear: 2019, confidence: "medium", altGroupId: 2594 },
  "Hidden Fates ETB Promo": { groupId: 2480, abbreviation: "HIF", publishedYear: 2019, confidence: "medium", altGroupId: 2594 },
  "Japanese Base Set": { groupId: 604, abbreviation: "BS", publishedYear: 1999, confidence: "medium", altGroupId: 605 },
  "Journey Together": { groupId: 24073, abbreviation: "JTG", publishedYear: 2025, confidence: "high", altGroupId: 23821 },
  "Jungle": { groupId: 635, abbreviation: "JU", publishedYear: 1999, confidence: "high", altGroupId: 23722 },
  "Lost Origin": { groupId: 3118, abbreviation: "SWSH11", publishedYear: 2022, confidence: "medium", altGroupId: 3172 },
  "M-P Promo": { groupId: 24423, abbreviation: "M-P", publishedYear: 2025, confidence: "high", altGroupId: 24607 },
  "Mega Evolution": { groupId: 24380, abbreviation: "MEG", publishedYear: 2025, confidence: "medium", altGroupId: 24451 },
  "Neo Destiny": { groupId: 1444, abbreviation: "N4", publishedYear: 2002, confidence: "high", altGroupId: 1389 },
  "Neo Discovery": { groupId: 1434, abbreviation: "N2", publishedYear: 2001, confidence: "high", altGroupId: 1389 },
  "Neo Genesis": { groupId: 1396, abbreviation: "N1", publishedYear: 2000, confidence: "high", altGroupId: 24017 },
  "Neo Revelation": { groupId: 1389, abbreviation: "N3", publishedYear: 2001, confidence: "high", altGroupId: 1434 },
  "Next Destinies": { groupId: 1412, abbreviation: "NXD", publishedYear: 2012, confidence: "high", altGroupId: 1386 },
  "Obsidian Flames": { groupId: 23228, abbreviation: "OBF", publishedYear: 2023, confidence: "high", altGroupId: 17688 },
  "Paldea Evolved": { groupId: 23120, abbreviation: "PAL", publishedYear: 2023, confidence: "high", altGroupId: 17688 },
  "Paldean Fates": { groupId: 23353, abbreviation: "PAF", publishedYear: 2024, confidence: "high", altGroupId: 23381 },
  "Phantasmal Flames": { groupId: 24448, abbreviation: "PFL", publishedYear: 2025, confidence: "high", altGroupId: 23821 },
  "Play! Pokemon Promo": { groupId: 1378, abbreviation: "LM", publishedYear: 2006, confidence: "medium", altGroupId: 1379 },
  "POKEMON GO": { groupId: 3064, abbreviation: "PGO", publishedYear: 2022, confidence: "medium", altGroupId: 23641 },
  "POKEMON JAPANESE EXPANSION 20TH ANNIVERSARY": { groupId: 23982, abbreviation: "CP6", publishedYear: 2016, confidence: "high", altGroupId: 23880 },
  "POKEMON PFL EN-PHANTASMAL FLAMES": { groupId: 24448, abbreviation: "PFL", publishedYear: 2025, confidence: "high", altGroupId: 23821 },
  "Pokemon Snap Promo": { groupId: 604, abbreviation: "BS", publishedYear: 1999, confidence: "medium", altGroupId: 630 },
  "POKEMON SUN & MOON GUARDIANS RISING": { groupId: 1919, abbreviation: "SM02", publishedYear: 2017, confidence: "medium", altGroupId: 23692 },
  "Pokemon the Movie 2000 Promo": { groupId: 605, abbreviation: "BS2", publishedYear: 2000, confidence: "medium", altGroupId: 1373 },
  "POP Series 5": { groupId: 1414, abbreviation: "POP", publishedYear: 2026, confidence: "medium", altGroupId: 1422 },
  "Prismatic Evolutions": { groupId: 23821, abbreviation: "PRE", publishedYear: 2025, confidence: "high", altGroupId: 24073 },
  "Prismatic Evolutions ETB Promo": { groupId: 23821, abbreviation: "PRE", publishedYear: 2025, confidence: "high", altGroupId: 24073 },
  "Scarlet & Violet 151": { groupId: 23237, abbreviation: "MEW", publishedYear: 2023, confidence: "medium", altGroupId: 22872 },
  "Shining Fates": { groupId: 2754, abbreviation: "SHF", publishedYear: 2021, confidence: "medium", altGroupId: 2781 },
  "Silver Tempest": { groupId: 3170, abbreviation: "SWSH12", publishedYear: 2022, confidence: "medium", altGroupId: 17674 },
  "Skyridge": { groupId: 1372, abbreviation: "SK", publishedYear: 2003, confidence: "high", altGroupId: 1376 },
  "Southern Islands": { groupId: 648, abbreviation: "SI", publishedYear: 2001, confidence: "high", altGroupId: 1389 },
  "Stellar Crown": { groupId: 23537, abbreviation: "SCR", publishedYear: 2024, confidence: "high", altGroupId: 23615 },
  "Surging Sparks": { groupId: 23651, abbreviation: "SSP", publishedYear: 2024, confidence: "high", altGroupId: 23353 },
  "SV-P Promo": { groupId: 22872, abbreviation: "SVP", publishedYear: 2023, confidence: "medium", altGroupId: 23779 },
  "SVP Black Star Promo (Van Gogh Museum)": { groupId: 22872, abbreviation: "SVP", publishedYear: 2023, confidence: "medium", altGroupId: 23779 },
  "SWSH Black Star Promo": { groupId: 2585, abbreviation: "SWSH01", publishedYear: 2020, confidence: "medium", altGroupId: 2626 },
  "Team Rocket": { groupId: 1373, abbreviation: "TR", publishedYear: 2000, confidence: "high", altGroupId: 1428 },
  "Team Up": { groupId: 2377, abbreviation: "SM9", publishedYear: 2019, confidence: "high", altGroupId: 23868 },
  "Terastal Festival ex": { groupId: 23909, abbreviation: "SV8a", publishedYear: 2024, confidence: "medium", altGroupId: 23796 },
  "Topps Chrome Series 1": { groupId: 605, abbreviation: "BS2", publishedYear: 2000, confidence: "medium", altGroupId: 1373 },
  "Triplet Beat": { groupId: 23598, abbreviation: "SV1a", publishedYear: 2023, confidence: "high", altGroupId: 17688 },
  "Trophy": { groupId: 604, abbreviation: "BS", publishedYear: 1999, confidence: "medium", altGroupId: 630 },
  "Twilight Masquerade": { groupId: 23473, abbreviation: "TWM", publishedYear: 2024, confidence: "high", altGroupId: 23353 },
  "Ultra Prism": { groupId: 2178, abbreviation: "SM05", publishedYear: 2018, confidence: "high", altGroupId: 23695 },
  "Unified Minds": { groupId: 2464, abbreviation: "SM11", publishedYear: 2019, confidence: "high", altGroupId: 2377 },
  "Vivid Voltage": { groupId: 2701, abbreviation: "SWSH04", publishedYear: 2020, confidence: "high", altGroupId: 2585 },
  "VS Series": { groupId: 24180, abbreviation: null, publishedYear: 2001, confidence: "medium", altGroupId: 648 },
  "World Championships Promo": { groupId: 24205, abbreviation: null, publishedYear: 2026, confidence: "medium", altGroupId: 23802 },
  "XY Black Star Promo": { groupId: 23887, abbreviation: "XY", publishedYear: 2017, confidence: "medium", altGroupId: 1387 },
  "XY Evolutions": { groupId: 23887, abbreviation: "XY", publishedYear: 2017, confidence: "medium", altGroupId: 1842 },
  "XY Promo": { groupId: 1387, abbreviation: "XY", publishedYear: 2014, confidence: "high", altGroupId: 23908 },
};

/**
 * Look up a curated PSA set name → tcg_groups bridge entry.
 * Returns null if the PSA set isn't in our alias table or has no tcg_group_id.
 * Match is exact (case-sensitive) on the psa_set_name as it appears in graded_card_identities.
 */
export function aliasForPsaSet(psaSetName: string): PsaAlias | null {
  return aliases[psaSetName] ?? null;
}
