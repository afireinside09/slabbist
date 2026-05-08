#!/usr/bin/env -S deno run --allow-read --allow-env

/**
 * validate-csv.ts
 *
 * Purpose:
 *   Strict schema check on docs/data/psa-tcggroup-aliases.csv.
 *   No live API calls — safe to run offline and as a pre-commit hook.
 *
 * Usage:
 *   ./scripts/validate-csv.ts
 *
 *   # As a pre-commit hook (add to .git/hooks/pre-commit or husky):
 *   deno run --allow-read scripts/validate-csv.ts
 *
 * Expected output (clean):
 *   Validating docs/data/psa-tcggroup-aliases.csv ...
 *   ✓ 87 rows — all valid
 *
 * Expected output (errors):
 *   Validating docs/data/psa-tcggroup-aliases.csv ...
 *   [row  4] wrong column count: expected 15, got 14
 *   [row  7] psa_set_name is empty
 *   [row 12] psa_count is not a positive integer: "abc"
 *   [row 15] confidence is invalid: "maybe" (allowed: high, medium, low, none, verified, "")
 *   4 error(s) in 87 rows
 *
 * Exit code: 0 if clean, 1 if any errors.
 */

// ── Config ────────────────────────────────────────────────────────────────────

const CSV_PATH = "docs/data/psa-tcggroup-aliases.csv";

const EXPECTED_HEADERS = [
  "psa_set_name",
  "psa_years",
  "psa_count",
  "tcg_group_id",
  "tcg_group_name",
  "tcg_abbreviation",
  "tcg_published_year",
  "confidence",
  "alt_2_id",
  "alt_2_name",
  "alt_2_score",
  "alt_3_id",
  "alt_3_name",
  "alt_3_score",
  "notes",
];

const VALID_CONFIDENCE = new Set(["high", "medium", "low", "none", "verified", ""]);

const COLUMN_COUNT = EXPECTED_HEADERS.length; // 15

// ANSI colours
const isTTY = Deno.stdout.isTerminal?.() ?? false;
const RED = isTTY ? "\x1b[31m" : "";
const GREEN = isTTY ? "\x1b[32m" : "";
const RESET = isTTY ? "\x1b[0m" : "";

// ── Minimal CSV parser (handles quoted fields + embedded commas) ──────────────

function parseRow(line: string): string[] {
  const fields: string[] = [];
  let i = 0;
  while (i <= line.length) {
    if (i === line.length) {
      // Line ended after a comma — emit final empty field
      // (only reached when previous iteration consumed a trailing comma)
      break;
    }
    if (line[i] === '"') {
      // Quoted field
      let field = "";
      i++; // skip opening quote
      while (i < line.length) {
        if (line[i] === '"' && line[i + 1] === '"') {
          field += '"';
          i += 2;
        } else if (line[i] === '"') {
          i++; // skip closing quote
          break;
        } else {
          field += line[i++];
        }
      }
      fields.push(field);
      if (i < line.length && line[i] === ",") i++; // skip comma
    } else {
      // Unquoted field
      const comma = line.indexOf(",", i);
      if (comma === -1) {
        fields.push(line.slice(i));
        break;
      } else {
        fields.push(line.slice(i, comma));
        i = comma + 1;
        // If we just consumed the last comma (it was trailing), push empty field
        if (i === line.length) {
          fields.push("");
          break;
        }
      }
    }
  }
  return fields;
}

// ── Validators ────────────────────────────────────────────────────────────────

function isPositiveInt(s: string): boolean {
  const n = parseInt(s, 10);
  return !isNaN(n) && n > 0 && String(n) === s.trim();
}

function isEmptyOrPositiveInt(s: string): boolean {
  return s === "" || isPositiveInt(s);
}

function isEmptyOrNumber(s: string): boolean {
  if (s === "") return true;
  return !isNaN(parseFloat(s)) && isFinite(Number(s));
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`Validating ${CSV_PATH} ...`);

  let text = "";
  try {
    text = await Deno.readTextFile(CSV_PATH);
  } catch {
    console.error(`${RED}Cannot read ${CSV_PATH}. Aborting.${RESET}`);
    Deno.exit(1);
  }

  // Split into lines (handle \r\n)
  const rawLines = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n");
  // Drop trailing empty line
  const lines = rawLines[rawLines.length - 1] === ""
    ? rawLines.slice(0, -1)
    : rawLines;

  if (lines.length === 0) {
    console.error(`${RED}CSV file is empty.${RESET}`);
    Deno.exit(1);
  }

  // Validate header
  const headerFields = parseRow(lines[0]);
  let headerOk = true;
  if (headerFields.length !== COLUMN_COUNT) {
    console.error(
      `${RED}[header] expected ${COLUMN_COUNT} columns, got ${headerFields.length}${RESET}`
    );
    headerOk = false;
  } else {
    for (let col = 0; col < COLUMN_COUNT; col++) {
      if (headerFields[col] !== EXPECTED_HEADERS[col]) {
        console.error(
          `${RED}[header] col ${col + 1}: expected "${EXPECTED_HEADERS[col]}", got "${headerFields[col]}"${RESET}`
        );
        headerOk = false;
      }
    }
  }
  if (!headerOk) {
    console.error("Header validation failed. Fix headers before proceeding.");
    Deno.exit(1);
  }

  const dataLines = lines.slice(1);
  const totalRows = dataLines.length;
  const errorMessages: string[] = [];

  for (let i = 0; i < dataLines.length; i++) {
    const line = dataLines[i];
    if (line.trim() === "") continue; // skip blank lines

    const rowNum = i + 2; // 1-based, row 1 = header
    const fields = parseRow(line);

    // Column count
    if (fields.length !== COLUMN_COUNT) {
      errorMessages.push(
        `[row ${String(rowNum).padStart(3)}] wrong column count: expected ${COLUMN_COUNT}, got ${fields.length}`
      );
      continue; // can't meaningfully validate further
    }

    const [
      psa_set_name,
      _psa_years,
      psa_count,
      tcg_group_id,
      _tcg_group_name,
      _tcg_abbreviation,
      _tcg_published_year,
      confidence,
      _alt_2_id,
      _alt_2_name,
      alt_2_score,
      _alt_3_id,
      _alt_3_name,
      alt_3_score,
      _notes,
    ] = fields;

    // psa_set_name non-empty
    if (!psa_set_name || psa_set_name.trim() === "") {
      errorMessages.push(
        `[row ${String(rowNum).padStart(3)}] psa_set_name is empty`
      );
    }

    // psa_count is a positive int
    if (!isPositiveInt(psa_count.trim())) {
      errorMessages.push(
        `[row ${String(rowNum).padStart(3)}] psa_count is not a positive integer: "${psa_count}"`
      );
    }

    // tcg_group_id is empty OR a positive int
    if (!isEmptyOrPositiveInt(tcg_group_id.trim())) {
      errorMessages.push(
        `[row ${String(rowNum).padStart(3)}] tcg_group_id is invalid: "${tcg_group_id}" (must be empty or a positive integer)`
      );
    }

    // confidence is one of the allowed values
    const conf = confidence.trim();
    if (!VALID_CONFIDENCE.has(conf)) {
      errorMessages.push(
        `[row ${String(rowNum).padStart(3)}] confidence is invalid: "${conf}" (allowed: ${[...VALID_CONFIDENCE].map((v) => v === "" ? '""' : v).join(", ")})`
      );
    }

    // alt_2_score is empty OR a number
    if (!isEmptyOrNumber(alt_2_score.trim())) {
      errorMessages.push(
        `[row ${String(rowNum).padStart(3)}] alt_2_score is not a number: "${alt_2_score}"`
      );
    }

    // alt_3_score is empty OR a number
    if (!isEmptyOrNumber(alt_3_score.trim())) {
      errorMessages.push(
        `[row ${String(rowNum).padStart(3)}] alt_3_score is not a number: "${alt_3_score}"`
      );
    }
  }

  if (errorMessages.length > 0) {
    for (const msg of errorMessages) {
      console.log(`${RED}${msg}${RESET}`);
    }
    console.log(`\n${errorMessages.length} error(s) in ${totalRows} rows`);
    Deno.exit(1);
  } else {
    console.log(`${GREEN}✓ ${totalRows} rows — all valid${RESET}`);
    Deno.exit(0);
  }
}

main().catch((err) => {
  console.error("Fatal:", err);
  Deno.exit(1);
});
