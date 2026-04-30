// supabase/functions/cert-lookup/types.ts

export type GradingService = "PSA" | "BGS" | "CGC" | "SGC" | "TAG";

export interface CertLookupRequest {
  grader: GradingService;
  cert_number: string;
}

export interface CertLookupCard {
  set_name: string;
  card_number: string | null;
  card_name: string;
  variant: string | null;
  year: number | null;
  language: "en" | "jp";
}

export interface CertLookupResponse {
  identity_id: string;
  graded_card_id: string;
  grading_service: GradingService;
  grade: string;
  card: CertLookupCard;
  cache_hit: boolean;
}

/** Shape returned by PSA Public API GetByCertNumber. Only the fields we care
 * about are typed; PSA returns more (PopulationHigher, etc.) that we tuck into
 * `graded_cards.source_payload` as raw JSON for later use. */
export interface PSACertResponse {
  PSACert: {
    CertNumber: string;
    SpecID?: number;
    LabelType?: string;
    Year?: string;
    Brand?: string;
    Category?: string;
    CardNumber?: string;
    Subject?: string;
    Variety?: string;
    GradeDescription?: string;
    CardGrade?: string;
    TotalPopulation?: number;
    PopulationHigher?: number;
  };
}
