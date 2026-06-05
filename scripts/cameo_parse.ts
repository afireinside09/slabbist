export type ParsedCard = {
  cardName: string;
  setName: string;
  cardNumber: string;
  notes: string;
  generation: string;
};

export type ParsedSubject = {
  kind: "pokemon" | "trainer";
  ndex: number | null;
  region: string | null;
  name: string;
  cards: ParsedCard[];
};

type SheetOpts = { generation: string; kind: "pokemon" | "trainer" };

/**
 * Turns position-based, header-stripped CSV rows into subjects with their
 * cards. Handles two independent forward-fills:
 *   - column 0 (ndex for pokemon, region for trainers) and column 1 (name)
 *     forward-fill down; a non-empty column 1 starts a new subject.
 *   - column 2 (card name) forward-fills down within a subject; a reprint row
 *     leaves it blank but supplies a new set/number. A new subject always
 *     carries its own card name, which replaces the running one.
 * Fully-empty rows are skipped.
 */
export function parseCameoSheet(rows: string[][], opts: SheetOpts): ParsedSubject[] {
  const subjects: ParsedSubject[] = [];
  let current: ParsedSubject | null = null;
  let region: string | null = null;   // trainer region carries across subjects
  let cardName = "";

  for (const row of rows) {
    const col0 = (row[0] ?? "").trim();
    const name = (row[1] ?? "").trim();
    const rawCard = (row[2] ?? "").trim();
    const setName = (row[3] ?? "").trim();
    const cardNumber = (row[4] ?? "").trim();
    const notes = (row[5] ?? "").trim();

    if (!col0 && !name && !rawCard && !setName && !cardNumber && !notes) continue;

    if (opts.kind === "trainer" && col0) region = col0;

    if (name) {
      current = {
        kind: opts.kind,
        ndex: opts.kind === "pokemon" ? (col0 ? Number(col0) : null) : null,
        region: opts.kind === "trainer" ? region : null,
        name,
        cards: [],
      };
      subjects.push(current);
      cardName = ""; // reset; this row's card name is set next
    }

    if (rawCard) cardName = rawCard;
    if (!current) continue; // defensive: data before any subject

    current.cards.push({
      cardName,
      setName,
      cardNumber,
      notes,
      generation: opts.generation,
    });
  }

  return subjects;
}
