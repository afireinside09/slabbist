// src/graded/match/listing-matcher.ts
// Strict acceptance check for an eBay listing against a specific
// (product_id, sub_type_name) we believe it represents. The whole
// point of this layer is preventing "Charizard listing got attached
// to Blastoise" — false positives in eBay search are common, so we
// reject anything we can't positively tie to *this* card.
//
// Hard rejects:
//   1. Title doesn't match the grading regex (PSA 10 / BGS 9.5 / …).
//      We're storing graded listings only.
//   2. Title contains a blocklist token: lot of, bundle, repack,
//      mystery box, proxy, custom, fake, replica, art card, metal
//      card, playmat, multi-pack patterns ("x10", "10x").
//   3. Card-number filter:
//        - If the source card has a numeric `card_number` like
//          "008/102", the title must contain "<num>/<denom>" with
//          flexible zero-padding and optional spaces around the
//          slash.
//        - Cards without a card_number (some JP cards) fall back to
//          requiring the card-name token — but we reject if the
//          card name is too short / too generic to be safely
//          matched on its own.
//   4. Sub-type compatibility. If the card variant is a Holofoil /
//      Reverse Holofoil / 1st Edition variant, the title must hint
//      at that variant; if the variant is "Normal", we reject any
//      title that explicitly mentions "Holo", "Reverse", or
//      "1st Edition" — those would be the wrong variant.
//
// Returns the parsed grading service + grade on success, so the
// ingest layer can store them without re-parsing.

export type GradingService = "PSA" | "BGS" | "CGC" | "SGC" | "TAG" | "HGA" | "GMA";

export interface MatchInput {
  /** Card name + number, exactly as stored in tcg_products.name. */
  productName: string;
  /** Optional card number — when present it's the strongest signal. */
  cardNumber: string | null;
  /** Sub-type variant: "Normal" / "Holofoil" / "Reverse Holofoil" / etc. */
  subTypeName: string;
}

export type MatchResult =
  | { ok: true; gradingService: GradingService; grade: string }
  | { ok: false; reason: string };

const GRADE_RE = /\b(PSA|BGS|CGC|SGC|TAG|HGA|GMA)\s*(10(?:\.0)?|[1-9](?:\.5)?)\b/i;

const BLOCK_RE = new RegExp(
  [
    "\\blot\\b",
    "\\bbundle\\b",
    "\\brepack\\b",
    "\\bmystery\\b",
    "\\bproxy\\b",
    "\\bcustom\\b",
    "\\bfake\\b",
    "\\breplica\\b",
    "\\bart\\s+card\\b",
    "\\bmetal\\s+card\\b",
    "\\bplaymat\\b",
    "\\bsticker\\b",
    "\\bx\\s*\\d{2,}\\b",
    "\\b\\d{2,}\\s*x\\b",
  ].join("|"),
  "i",
);

const VARIANT_HOLO_RE = /\b(holo(?:foil)?)\b/i;
const VARIANT_REVERSE_RE = /\b(reverse(?:\s+holo(?:foil)?)?|rev\s*holo)\b/i;
const VARIANT_FIRST_ED_RE = /\b(1st\s*ed(?:ition)?|first\s*ed(?:ition)?)\b/i;

export function acceptListing(title: string, card: MatchInput): MatchResult {
  // 1. Graded check — title must announce a service + grade.
  const gradeMatch = title.match(GRADE_RE);
  if (!gradeMatch) {
    return { ok: false, reason: "no graded service+grade in title" };
  }
  const gradingService = gradeMatch[1]!.toUpperCase() as GradingService;
  const grade = gradeMatch[2]!.replace(/\.0$/, "");

  // 2. Blocklist (lots / proxies / repacks / playmats / multi-packs).
  if (BLOCK_RE.test(title)) {
    return { ok: false, reason: "blocklist token in title" };
  }

  // 3. Card-number identity check (the strongest signal we have).
  if (card.cardNumber) {
    const patterns = cardNumberPatterns(card.cardNumber);
    const numFound = patterns.some((re) => re.test(title));
    if (!numFound) {
      return { ok: false, reason: "card number not found in title" };
    }
  } else {
    // Fallback for cards without a stored card_number: require the
    // primary card-name token, and reject if the name is too short
    // to be reliably distinguishing.
    const primary = primaryNameToken(card.productName);
    if (!primary || primary.length < 4) {
      return { ok: false, reason: "no card_number and name too generic for fallback" };
    }
    if (!new RegExp(`\\b${escapeRegex(primary)}\\b`, "i").test(title)) {
      return { ok: false, reason: "card name not found in title" };
    }
  }

  // 4. Variant compatibility. The card_number alone doesn't
  // distinguish Holofoil from Normal — same printed number, different
  // variant. Cross-check the title's variant cue against the source.
  const wants = canonicalVariant(card.subTypeName);
  const cues = {
    holo: VARIANT_HOLO_RE.test(title),
    reverse: VARIANT_REVERSE_RE.test(title),
    firstEd: VARIANT_FIRST_ED_RE.test(title),
  };
  // "reverse" implies "holo" tokens too; treat reverse as primary.
  if (cues.reverse) cues.holo = false;

  switch (wants) {
    case "normal":
      // Normal Pokémon listings shouldn't loudly advertise a foil
      // variant. (PSA labels say "HOLO" too — but title sellers who
      // mean Normal usually don't include the word.)
      if (cues.holo || cues.reverse || cues.firstEd) {
        return { ok: false, reason: "title advertises a non-Normal variant" };
      }
      break;
    case "holo":
      if (!cues.holo && !cues.reverse) {
        return { ok: false, reason: "expected Holofoil cue in title" };
      }
      if (cues.reverse) {
        return { ok: false, reason: "title is Reverse Holofoil; card is Holofoil" };
      }
      if (cues.firstEd && !canonicalIsFirstEdition(card.subTypeName)) {
        return { ok: false, reason: "title is 1st Edition; card is not" };
      }
      break;
    case "reverse":
      if (!cues.reverse) {
        return { ok: false, reason: "expected Reverse Holofoil cue in title" };
      }
      break;
    case "firstEd":
      if (!cues.firstEd) {
        return { ok: false, reason: "expected 1st Edition cue in title" };
      }
      break;
    case "firstEdHolo":
      if (!cues.firstEd || !cues.holo) {
        return { ok: false, reason: "expected 1st Edition + Holofoil cue in title" };
      }
      break;
    case "unlimited":
    case "unlimitedHolo":
      // "Unlimited" is rarely advertised explicitly; we'd reject too
      // many true matches if we required it. Accept these.
      break;
  }

  return { ok: true, gradingService, grade };
}

// ---------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------

function canonicalVariant(subType: string): Variant {
  const s = subType.toLowerCase();
  if (s === "normal") return "normal";
  if (s === "holofoil") return "holo";
  if (s === "reverse holofoil") return "reverse";
  if (s === "1st edition") return "firstEd";
  if (s === "1st edition holofoil") return "firstEdHolo";
  if (s === "unlimited") return "unlimited";
  if (s === "unlimited holofoil") return "unlimitedHolo";
  // Unknown sub-types: don't reject on variant grounds.
  return "normal";
}

function canonicalIsFirstEdition(subType: string): boolean {
  return /1st edition/i.test(subType);
}

type Variant =
  | "normal"
  | "holo"
  | "reverse"
  | "firstEd"
  | "firstEdHolo"
  | "unlimited"
  | "unlimitedHolo";

function primaryNameToken(productName: string): string {
  // Strip any trailing " - <num>/<denom>" or "(<num>)" so the leading
  // token reflects the card name.
  const stripped = productName.replace(/\s*[-(]\s*[\dA-Za-z/]+.*$/, "").trim();
  const first = stripped.split(/\s+/)[0] ?? "";
  return first;
}

/// Build regexes that match the card number across the formats
/// sellers actually use. For "008/102" we accept "008/102", "8/102",
/// "8 / 102". We do NOT accept the bare "8" — too many cards share
/// the same numerator across sets.
export function cardNumberPatterns(cardNumber: string): RegExp[] {
  const trimmed = cardNumber.trim();
  const slash = trimmed.match(/^(\w+?)\s*\/\s*(\w+)$/);
  if (slash) {
    const left = slash[1]!;
    const right = slash[2]!;
    const stripped = left.replace(/^0+/, "") || "0";
    // Two regexes: the canonical form (zero-stripped) and a permissive
    // form that accepts any leading zero count plus optional spaces
    // around the slash.
    return [
      new RegExp(
        `\\b0*${escapeRegex(stripped)}\\s*/\\s*${escapeRegex(right)}\\b`,
        "i",
      ),
      new RegExp(
        `\\b${escapeRegex(left)}\\s*/\\s*${escapeRegex(right)}\\b`,
        "i",
      ),
    ];
  }
  // Non-slash numbers (e.g. "TG14"): require an exact, word-bounded
  // match in the title.
  return [new RegExp(`\\b${escapeRegex(trimmed)}\\b`, "i")];
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
