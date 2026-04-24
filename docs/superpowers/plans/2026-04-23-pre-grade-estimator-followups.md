# Pre-grade Estimator — Deferred Followups

Items surfaced by code review during initial implementation but explicitly deferred to keep the side-quest scope tight. None block v1 launch.

## T6 — `/grade-estimate` Edge Function

| ID | Severity | Description | Why deferred |
|---|---|---|---|
| C1 | Critical | TOCTOU race on rate-limit check: concurrent requests within ms can both pass the count check and double-spend slots | 20/day cap is a soft control; worst-case ~$0.40/day overspend per abuser; proper fix needs a separate quota table |
| C2 | Critical | `downloadAsBase64` throws into uncaught territory; storage 404 surfaces as opaque 500 instead of 422 | iOS uploads happen immediately before the call so 404 is rare; client retries are safe |
| I1 | Important | Non-object JSON body (`null`, array, string) crashes the validation block | Only the iOS client calls this endpoint; client always sends a valid object |
| I3 | Important | `stop_reason === 'max_tokens'` wastes the retry attempt | 1500 tokens is generous for the schema; truncation is unlikely in practice |
| I4 | Important | Rate-limit window is rolling 24h; spec says "midnight UTC" reset | Rolling is also reasonable; pick the consistent answer when wiring the iOS error UI |
| I6 | Important | Thumbnail path derivation by regex; if iOS deviates from `/front.jpg` convention, thumb path silently equals original | iOS uploader (T13) hardcodes the convention; defensive validation pending if a second uploader appears |
| M1 | Minor | `serviceRoleClient()` factory called twice; could be created once and reused | Micro-optimization; Supabase client is cheap to construct |

If the feature gets meaningful traffic, fix C1 (quota table), C2 (try/catch + 422), I1 (type guard), and I4 (pick midnight or rolling, document). I3, I6, M1 are nice-to-haves.
