# eBay Partner Network affiliate links in Movers

**Date:** 2026-05-08
**Status:** Draft

## Goal

Convert all eBay listing links shown in the Movers tab into eBay Partner Network (EPN) affiliate links so Slabbist earns commission on resulting sales, and surface a clear-and-conspicuous disclosure near those links.

## Background

The Movers tab surfaces curated eBay listings for popular slabs. Today the user taps a listing and we open the raw eBay item URL via `UIApplication.shared.open(...)`. URLs are stored verbatim in `mover_ebay_listings.url` (via the scraper) and returned through the `get_ebay_listings()` RPC into the iOS DTO `EbayListingBrowseRowDTO.url`. There is no existing EPN integration in the codebase.

Slabbist is now an eBay Partner Network publisher. Campaign ID: `5339152656`.

## Non-goals

- No scraper or DB schema changes — raw URLs continue to be stored as-is.
- No rover.ebay.com redirect URLs — we use the modern direct-link parameter form.
- No analytics beyond the `customid` tag (we can layer click tracking later).
- No changes to surfaces outside Movers — exploration confirmed no other eBay link opens exist in the iOS code.
- No Android/web client work — none exists today.

## Approach

**Client-side rewrite at the open point.** Append EPN tracking parameters to the eBay URL inside the iOS app immediately before opening it. The DB stays clean, the scraper stays unchanged, and the campid lives in build configuration so it can be flipped without code edits.

## URL format

EPN smart-link parameters appended to the existing eBay item URL:

| Param | Value | Notes |
|---|---|---|
| `mkcid` | `1` | Channel: smart link |
| `mkrid` | `711-53200-19255-0` | US site rotation ID |
| `siteid` | `0` | US |
| `campid` | `5339152656` | Slabbist campaign |
| `customid` | `slabbist-ios` | Free-form tracking tag |
| `toolid` | `10001` | Required by EPN |
| `mkevt` | `1` | Required by EPN |

If the raw URL already contains query params, the rewriter merges rather than overwriting. If the host is not `ebay.com` / `*.ebay.com`, the URL passes through unchanged. If `EPN_CAMPAIGN_ID` is missing/empty (e.g. dev build with no xcconfig), the original URL is returned unchanged so the app remains usable.

## Components

1. **`ios/slabbist/slabbist/Core/Utilities/EbayAffiliateLink.swift`** (new, ~40 lines)
   - `enum EbayAffiliateLink` with `static func rewrite(_ raw: String) -> URL?`.
   - Reads `EPNCampaignID` (and optional `EPNCustomID`) from `Bundle.main.infoDictionary`.
   - Validates host before rewriting; returns the original URL for non-eBay hosts.
   - Uses `URLComponents` to safely merge query items.

2. **`ios/slabbist/slabbist/Config/Slabbist.xcconfig`** (or wherever the existing xcconfig lives — check before editing)
   - Add `EPN_CAMPAIGN_ID = 5339152656`
   - Add `EPN_CUSTOM_ID = slabbist-ios`

3. **`ios/slabbist/slabbist/Info.plist`**
   - Add `EPNCampaignID` → `$(EPN_CAMPAIGN_ID)`
   - Add `EPNCustomID` → `$(EPN_CUSTOM_ID)`

4. **`ios/slabbist/slabbist/Features/Movers/EbayProductListingsView.swift:151`**
   - Replace `URL(string: listing.url)` with `EbayAffiliateLink.rewrite(listing.url)`.

5. **Disclosure caption** — small, secondary-styled line:
   > *Some links are affiliate links — Slabbist may earn a commission.*
   - Placement A: under the eBay Listings sub-tab header inside `MoversListView` (whole-tab visibility).
   - Placement B: under the product header inside `EbayProductListingsView` (visible at the moment of tap).
   - Style: `.font(.caption2).foregroundStyle(.secondary)`, single line, wraps as needed.

## Testing

- Unit test `EbayAffiliateLink.rewrite` for: vanilla `https://www.ebay.com/itm/<id>`, URL with existing query params, non-eBay host (passthrough), missing campid (passthrough), malformed URL.
- Manual: tap a listing in Movers → confirm the opened URL contains `campid=5339152656` and `customid=slabbist-ios`.
- Manual: confirm the disclosure caption appears in both the Movers tab eBay sub-tab and the drill-down view.

## Risks

- xcconfig key not propagating to Info.plist if the project doesn't already use xcconfig substitution. Mitigation: verify Slabbist's project setup before wiring; fall back to a Swift constant + warn the user if xcconfig isn't configured.
- EPN site rotation ID (`mkrid`) is US-only. Acceptable: Slabbist users are US-focused today.
