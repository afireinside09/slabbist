// @ts-nocheck — this file runs on Deno (Supabase Edge Functions). Local TS LSP can't resolve `Deno` or `https://` imports; runtime is correct.

export interface CenteringRatios {
  left: number;   // 0..1, distance from left photo edge to left card edge / total horizontal whitespace
  right: number;
  top: number;
  bottom: number;
}

export interface GradeEstimateRequest {
  front_image_path: string;
  back_image_path: string;
  centering_front: CenteringRatios;
  centering_back: CenteringRatios;
  include_other_graders: boolean;
}

export type SubGradeKey = 'centering' | 'corners' | 'edges' | 'surface';
export type Confidence = 'low' | 'medium' | 'high';
export type Verdict =
  | 'submit_economy'
  | 'submit_value'
  | 'submit_express'
  | 'do_not_submit'
  | 'borderline_reshoot';

export interface PerGraderReport {
  sub_grades: Record<SubGradeKey, number>;
  sub_grade_notes: Record<SubGradeKey, string>;
  composite_grade: number;
  confidence: Confidence;
  verdict: Verdict;
  verdict_reasoning: string;
}

export interface GradeEstimateLLMOutput extends PerGraderReport {
  other_graders: null | { bgs: PerGraderReport; cgc: PerGraderReport; sgc: PerGraderReport };
}
