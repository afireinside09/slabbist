// src/graded/title-extractor.ts
import type { GradedCardIdentityInput, GradingService } from "@/graded/models.js";

const JAPANESE_TOKENS = /\b(japanese|japan)\b|日本|ポケモン/i;

const SERVICE_GRADE = /\b(PSA|CGC|BGS|SGC|TAG)\s*[0-9]+(\.5)?\b/gi;

// Cert numbers must be stripped BEFORE card-number extraction so that
// "Cert #12345678" is not mistaken for a card number.
const CERT = /\b(?:cert(?:ificate)?)\s*#?\s*\d+/gi;

const NOISE = /gem\s*mint|pristine|\bnm\b|near\s*mint|\bunlimited\b|\bmint\b/gi;

const POKEMON_TCG = /pokémon|pokemon|tcg/gi;

// Card number patterns — tried in order.
// Pattern A: #<digits> optionally followed by /<digits>  →  capture just the leading digits
const CARD_NUM_HASH = /#(\d+)(?:\/\d+)?/;
// Pattern B: <digits>/<digits> standalone → capture full fraction as identity hint
const CARD_NUM_FRACTION = /\b(\d+)\/(\d+)\b/;

// Year: 4-digit number in 1990–2030, NOT preceded by # or /
// We use a lookbehind to exclude those cases.
const YEAR_RE = /(?<![#/])(?<!\d)(\b(?:19[9]\d|20[012]\d|2030)\b)(?!\d)/;

/**
 * Pure function. Extracts structured card identity fields from a raw eBay
 * listing title. Returns a `GradedCardIdentityInput` ready to upsert.
 *
 * @param title   Raw eBay listing title
 * @param service Grading service detected by the caller (e.g. "PSA")
 * @param grade   Grade string detected by the caller  (e.g. "10")
 */
export function extractIdentityFromEbayTitle(
  title: string,
  service: GradingService,
  grade: string,
): GradedCardIdentityInput {
  let working = title;

  // ── 1. Language detection ────────────────────────────────────────────────
  const language: "en" | "jp" = JAPANESE_TOKENS.test(working) ? "jp" : "en";
  // Strip the matched Japanese tokens from the working string.
  working = working.replace(/\b(japanese|japan)\b/gi, " ");
  working = working.replace(/日本|ポケモン/g, " ");

  // ── 2. Year ──────────────────────────────────────────────────────────────
  const yearMatch = YEAR_RE.exec(working);
  let year: number | null = null;
  if (yearMatch) {
    year = parseInt(yearMatch[1]!, 10);
    working = working.slice(0, yearMatch.index) + " " + working.slice(yearMatch.index + yearMatch[0].length);
  }

  // ── 2b. Strip cert/certificate numbers before card-number extraction ─────
  // Must run before step 3 so "Cert #12345678" is not mistaken for a card number.
  working = working.replace(CERT, " ");

  // ── 3. Card number ───────────────────────────────────────────────────────
  let cardNumber: string | null = null;

  const hashMatch = CARD_NUM_HASH.exec(working);
  if (hashMatch) {
    cardNumber = hashMatch[1]!;
    working = working.slice(0, hashMatch.index) + " " + working.slice(hashMatch.index + hashMatch[0].length);
  } else {
    const fracMatch = CARD_NUM_FRACTION.exec(working);
    if (fracMatch) {
      cardNumber = `${fracMatch[1]!}/${fracMatch[2]!}`;
      working = working.slice(0, fracMatch.index) + " " + working.slice(fracMatch.index + fracMatch[0].length);
    }
  }

  // ── 4. Service + grade token ─────────────────────────────────────────────
  // Build a pattern specific to the detected service/grade so we don't
  // accidentally strip part of the card name.
  const serviceGradeRe = new RegExp(
    `\\b${service}\\s*${grade.replace(".", "\\.")}(\\.5)?\\b`,
    "gi",
  );
  working = working.replace(serviceGradeRe, " ");
  // Also strip the generic form in case the caller's service/grade differs in
  // casing from the raw title.
  working = working.replace(SERVICE_GRADE, " ");

  // ── 5. Noise tokens ──────────────────────────────────────────────────────
  working = working.replace(NOISE, " ");

  // ── 6. Pokemon / TCG tokens ──────────────────────────────────────────────
  working = working.replace(POKEMON_TCG, " ");

  // ── 7. cardName ──────────────────────────────────────────────────────────
  const cardName = working.toLowerCase().replace(/\s+/g, " ").trim()
    || title.toLowerCase();

  return {
    game: "pokemon",
    language,
    setName: "",
    year,
    cardNumber,
    cardName,
    variant: null,
  };
}
