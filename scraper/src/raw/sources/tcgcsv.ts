import { z } from "zod";
import { httpJson } from "@/shared/http/fetch.js";
import type { TcgGroup, TcgProductRaw, TcgPriceRow } from "@/raw/models.js";

const BASE = "https://tcgcsv.com/tcgplayer";

const GroupsResponse = z.object({
  success: z.boolean(),
  errors: z.array(z.string()),
  results: z.array(
    z.object({
      groupId: z.number(),
      name: z.string(),
      abbreviation: z.string().nullable().optional(),
      isSupplemental: z.boolean().optional(),
      publishedOn: z.string().nullable().optional(),
      modifiedOn: z.string().nullable().optional(),
      categoryId: z.number(),
    }),
  ),
});

const ExtendedField = z.object({
  name: z.string(),
  displayName: z.string(),
  value: z.string(),
});

const ProductsResponse = z.object({
  success: z.boolean(),
  errors: z.array(z.string()),
  results: z.array(
    z.object({
      productId: z.number(),
      name: z.string(),
      cleanName: z.string().nullable().optional(),
      imageUrl: z.string().nullable().optional(),
      categoryId: z.number(),
      groupId: z.number(),
      url: z.string().nullable().optional(),
      modifiedOn: z.string().nullable().optional(),
      imageCount: z.number().nullable().optional(),
      presaleInfo: z
        .object({
          isPresale: z.boolean(),
          releasedOn: z.string().nullable(),
          note: z.string().nullable(),
        })
        .nullable()
        .optional(),
      extendedData: z.array(ExtendedField).default([]),
    }),
  ),
});

const PricesResponse = z.object({
  success: z.boolean(),
  errors: z.array(z.string()),
  results: z.array(
    z.object({
      productId: z.number(),
      subTypeName: z.string(),
      lowPrice: z.number().nullable(),
      midPrice: z.number().nullable(),
      highPrice: z.number().nullable(),
      marketPrice: z.number().nullable(),
      directLowPrice: z.number().nullable(),
    }),
  ),
});

export interface SourceOpts {
  userAgent: string;
}

export async function fetchGroups(categoryId: number, opts: SourceOpts): Promise<TcgGroup[]> {
  const raw = await httpJson(`${BASE}/${categoryId}/groups`, { userAgent: opts.userAgent });
  const parsed = GroupsResponse.parse(raw);
  return parsed.results.map((g) => ({
    groupId: g.groupId,
    categoryId: g.categoryId,
    name: g.name,
    abbreviation: g.abbreviation ?? null,
    isSupplemental: g.isSupplemental ?? false,
    publishedOn: g.publishedOn ?? null,
    modifiedOn: g.modifiedOn ?? null,
  }));
}

export async function fetchProducts(
  categoryId: number,
  groupId: number,
  opts: SourceOpts,
): Promise<TcgProductRaw[]> {
  const raw = await httpJson(`${BASE}/${categoryId}/${groupId}/products`, {
    userAgent: opts.userAgent,
  });
  const parsed = ProductsResponse.parse(raw);
  return parsed.results.map((p) => ({
    productId: p.productId,
    groupId: p.groupId,
    categoryId: p.categoryId,
    name: p.name,
    cleanName: p.cleanName ?? null,
    imageUrl: p.imageUrl ?? null,
    url: p.url ?? null,
    modifiedOn: p.modifiedOn ?? null,
    imageCount: p.imageCount ?? null,
    presaleInfo: p.presaleInfo ?? null,
    extendedData: p.extendedData,
  }));
}

export async function fetchPrices(
  categoryId: number,
  groupId: number,
  opts: SourceOpts,
): Promise<TcgPriceRow[]> {
  const raw = await httpJson(`${BASE}/${categoryId}/${groupId}/prices`, {
    userAgent: opts.userAgent,
  });
  const parsed = PricesResponse.parse(raw);
  return parsed.results.map((p) => ({ ...p }));
}
