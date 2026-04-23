export interface TcgCategory {
  categoryId: number;
  name: string;
  modifiedOn?: string;
}

export interface TcgGroup {
  groupId: number;
  categoryId: number;
  name: string;
  abbreviation: string | null;
  isSupplemental: boolean;
  publishedOn: string | null;
  modifiedOn: string | null;
}

export interface TcgExtendedField {
  name: string;
  displayName: string;
  value: string;
}

export interface TcgProductRaw {
  productId: number;
  groupId: number;
  categoryId: number;
  name: string;
  cleanName: string | null;
  imageUrl: string | null;
  url: string | null;
  modifiedOn: string | null;
  imageCount: number | null;
  presaleInfo: { isPresale: boolean; releasedOn: string | null; note: string | null } | null;
  extendedData: TcgExtendedField[];
}

export interface PokemonExtract {
  cardNumber: string | null;
  rarity: string | null;
  cardType: string | null;
  hp: string | null;
  stage: string | null;
}

export interface TcgPriceRow {
  productId: number;
  subTypeName: string;
  lowPrice: number | null;
  midPrice: number | null;
  highPrice: number | null;
  marketPrice: number | null;
  directLowPrice: number | null;
}

export const POKEMON_CATEGORIES = [
  { id: 3, language: "en" as const, label: "Pokémon (English)" },
  { id: 85, language: "jp" as const, label: "Pokémon (Japanese)" },
];
