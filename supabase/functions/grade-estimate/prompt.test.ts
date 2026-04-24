// @ts-nocheck — this file runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports; runtime is correct.
import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { buildUserPrompt, validateOutput } from './prompt.ts';

const validReport = {
  sub_grades: { centering: 8, corners: 7, edges: 8, surface: 9 },
  sub_grade_notes: {
    centering: 'L/R 55/45 within PSA 8 tolerance',
    corners: 'TR corner front shows light whitening',
    edges: 'left edge front has tiny dent at midpoint',
    surface: 'no visible scratches at this resolution',
  },
  composite_grade: 8,
  confidence: 'high',
  verdict: 'submit_value',
  verdict_reasoning: 'Solid 8 with consistent measurements',
  other_graders: null,
};

Deno.test('validateOutput accepts a well-formed report', () => {
  validateOutput(validReport);
});

Deno.test('validateOutput rejects composite > min(sub) + 1', () => {
  const bad = { ...validReport, composite_grade: 9.5 };  // min=7, allowed up to 8
  assertThrows(() => validateOutput(bad), Error, 'exceeds min(sub)');
});

Deno.test('validateOutput rejects empty sub_grade_notes', () => {
  const bad = { ...validReport, sub_grade_notes: { ...validReport.sub_grade_notes, corners: '' } };
  assertThrows(() => validateOutput(bad), Error, 'empty');
});

Deno.test('validateOutput rejects out-of-range sub_grade', () => {
  const bad = { ...validReport, sub_grades: { ...validReport.sub_grades, edges: 11 } };
  assertThrows(() => validateOutput(bad), Error, 'out of range');
});

Deno.test('validateOutput rejects unknown verdict', () => {
  const bad = { ...validReport, verdict: 'send_it' };
  assertThrows(() => validateOutput(bad), Error, 'verdict');
});

Deno.test('validateOutput recurses into other_graders when present', () => {
  const badOther = {
    ...validReport,
    other_graders: {
      bgs: { ...validReport, composite_grade: 9.5 }, // violates rule 4 inside bgs
      cgc: validReport,
      sgc: validReport,
    },
  };
  assertThrows(() => validateOutput(badOther), Error, 'other_graders.bgs');
});

Deno.test('buildUserPrompt formats centering as integer percentages', () => {
  const out = buildUserPrompt({
    centering_front: { left: 0.6, right: 0.4, top: 0.5, bottom: 0.5 },
    centering_back: { left: 0.5, right: 0.5, top: 0.5, bottom: 0.5 },
    include_other_graders: false,
  });
  assertEquals(out.includes('Front: L/R 60/40'), true);
  assertEquals(out.includes('"other_graders": null'), true);
});
