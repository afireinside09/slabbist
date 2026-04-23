// @ts-nocheck — this file runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports; runtime is correct.
import type { CenteringRatios, GradeEstimateLLMOutput } from './types.ts';

export const SYSTEM_PROMPT = `You are a hyper-critical card grader. Your job is to give the most pessimistic *defensible* PSA grade for the card in these photos. Real submissions cost real money; over-estimating is worse than under-estimating.

Hard rules — no exceptions:
1. Centering ratios are provided as ground truth measured by a calibrated computer-vision pipeline. Use them. Do not re-estimate centering.
2. For corners, edges, and surface: if you cannot clearly see the relevant area in the photo, score it as if it has wear. Do not score generously when the photo is ambiguous.
3. Each sub-grade explanation must reference a specific visible feature (e.g., "top-right corner of the front shows light whitening", "left edge of the back has a 2mm dent at the midpoint", "centering ratio L/R 60/40 is outside PSA 9 tolerance"). No generic prose.
4. The composite grade must be no higher than min(sub_grades) + 1. PSA composites do not average up past the weakest link.
5. If your confidence is "low", the composite must be at most median(sub_grades) - 1.
6. Output must validate against the JSON schema in the user message. Anything else is a failure.

PSA centering tolerances (front face is the binding face; back is informational):
- PSA 10: 55/45 or better
- PSA 9: 60/40 or better
- PSA 8: 65/35 or better
- PSA 7: 70/30 or better
- Worse than 70/30: capped at PSA 6 on centering

Verdict guidance:
- submit_express: composite ≥ 9.5 with high confidence
- submit_value:   composite 8.5-9 with medium-or-high confidence
- submit_economy: composite 7-8 with medium-or-high confidence
- do_not_submit:  composite < 7, OR confidence low and composite < 8.5
- borderline_reshoot: model believes a better photo could change the grade by ≥ 1 step`;

export function buildUserPrompt(args: {
  centering_front: CenteringRatios;
  centering_back: CenteringRatios;
  include_other_graders: boolean;
}): string {
  const { centering_front: f, centering_back: b, include_other_graders } = args;
  const otherGradersSchema = include_other_graders
    ? `,\n  "other_graders": { "bgs": <PerGraderReport>, "cgc": <PerGraderReport>, "sgc": <PerGraderReport> }`
    : `,\n  "other_graders": null`;

  return `Here is a raw (ungraded) trading card. The first image is the FRONT, the second is the BACK.

Measured centering ratios (ground truth — use as-is):
- Front: L/R ${pct(f.left, f.right)}, T/B ${pct(f.top, f.bottom)}
- Back:  L/R ${pct(b.left, b.right)}, T/B ${pct(b.top, b.bottom)}

Return ONLY a JSON object with this exact shape:
{
  "sub_grades":      { "centering": <1-10>, "corners": <1-10>, "edges": <1-10>, "surface": <1-10> },
  "sub_grade_notes": { "centering": "<string>", "corners": "<string>", "edges": "<string>", "surface": "<string>" },
  "composite_grade": <number, may include .5>,
  "confidence":      "low" | "medium" | "high",
  "verdict":         "submit_economy" | "submit_value" | "submit_express" | "do_not_submit" | "borderline_reshoot",
  "verdict_reasoning": "<string>"${otherGradersSchema}
}`;
}

function pct(a: number, b: number): string {
  const total = a + b || 1;
  return `${Math.round((a / total) * 100)}/${Math.round((b / total) * 100)}`;
}

const VALID_VERDICTS = new Set([
  'submit_economy', 'submit_value', 'submit_express', 'do_not_submit', 'borderline_reshoot',
]);
const VALID_CONFIDENCE = new Set(['low', 'medium', 'high']);
const SUB_KEYS = ['centering', 'corners', 'edges', 'surface'] as const;

export function validateOutput(raw: unknown): GradeEstimateLLMOutput {
  if (typeof raw !== 'object' || raw === null) throw new Error('output not an object');
  const o = raw as Record<string, unknown>;

  validateReport(o, 'top-level');

  if (o.other_graders !== null && o.other_graders !== undefined) {
    const og = o.other_graders as Record<string, unknown>;
    for (const k of ['bgs', 'cgc', 'sgc']) {
      const sub = og[k];
      if (typeof sub !== 'object' || sub === null) throw new Error(`other_graders.${k} missing`);
      validateReport(sub as Record<string, unknown>, `other_graders.${k}`);
    }
  }
  return raw as GradeEstimateLLMOutput;
}

function validateReport(o: Record<string, unknown>, label: string): void {
  const sg = o.sub_grades as Record<string, number> | undefined;
  const sn = o.sub_grade_notes as Record<string, string> | undefined;
  if (!sg || !sn) throw new Error(`${label}: missing sub_grades / sub_grade_notes`);
  for (const k of SUB_KEYS) {
    const v = sg[k];
    if (typeof v !== 'number' || v < 1 || v > 10) throw new Error(`${label}.sub_grades.${k}: out of range`);
    if (typeof sn[k] !== 'string' || !sn[k].trim()) throw new Error(`${label}.sub_grade_notes.${k}: empty`);
  }
  const c = o.composite_grade;
  if (typeof c !== 'number' || c < 1 || c > 10) throw new Error(`${label}.composite_grade: out of range`);

  // Enforce hard rule 4 (composite <= min(sub_grades) + 1) at validation time.
  const minSub = Math.min(...SUB_KEYS.map((k) => sg[k]));
  if (c > minSub + 1) throw new Error(`${label}.composite_grade ${c} exceeds min(sub) ${minSub} + 1`);

  if (typeof o.confidence !== 'string' || !VALID_CONFIDENCE.has(o.confidence as string)) {
    throw new Error(`${label}.confidence: invalid`);
  }
  if (typeof o.verdict !== 'string' || !VALID_VERDICTS.has(o.verdict as string)) {
    throw new Error(`${label}.verdict: invalid`);
  }
  if (typeof o.verdict_reasoning !== 'string' || !o.verdict_reasoning.trim()) {
    throw new Error(`${label}.verdict_reasoning: empty`);
  }
}
