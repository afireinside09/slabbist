export type GradingService = "PSA" | "CGC" | "BGS" | "SGC" | "TAG";
export type Language = "en" | "jp";

export interface GradedCardIdentityInput {
  game: "pokemon";
  language: Language;
  setName: string;
  setCode?: string | null;
  year?: number | null;
  cardNumber?: string | null;
  cardName: string;
  variant?: string | null;
}

export interface GradedCardIdentity extends GradedCardIdentityInput { id: string; }

export interface GradedCertRecord {
  gradingService: GradingService;
  certNumber: string;
  grade: string;
  gradedAt?: string | null;
  identity: GradedCardIdentityInput;
  sourcePayload: unknown;
}

export interface GradedSale {
  identity: GradedCardIdentityInput;
  gradingService: GradingService;
  grade: string;
  source: string;
  sourceListingId: string;
  soldPrice: number;
  soldAt: string;
  title: string;
  url: string;
  certNumber?: string | null;
}

export interface PopRow {
  identity: GradedCardIdentityInput;
  gradingService: GradingService;
  grade: string;
  population: number;
}
