# Collectible AI lookup on quick_add — design

Date: 2026-10-04
Status: approved in conversation, pending written-spec review

## Goal

On `/admin/collectibles/quick_add`, an admin picks a photo of a collectible and
clicks **"Identificar con IA"**. OpenAI identifies the piece from the image,
searches trusted sites live, and returns:

- identification (name, brand, series, scale, edition) with a confidence score
- launch date, with its source
- rarity level and the reasons behind it
- estimated price **in Mexico (MXN)** and **worldwide (USD)**, kept separate,
  each backed by links to the listings it came from

Empty form fields are pre-filled and stay editable; rarity, prices and sources
appear in a side panel. Nothing is saved to the product unless the admin submits
the form as today.

**Success:** photo → under a minute → name, launch date, rarity and both price
ranges with verifiable sources, so the admin prices a new piece faster.

## Decisions taken

| Question | Decision |
|---|---|
| Live search vs. model knowledge | Live web search for real prices |
| Price sources | Trusted-domain allowlist, Mexico and worldwide reported separately |
| Provider | OpenAI |
| What the result does to the form | Fill **empty** fields, editable; rest in a side panel |
| Trigger | Explicit button, never automatic on upload |
| Approach | One background Responses API call (image + `web_search` + strict JSON schema), page polls for the result |
| Gem | Upgrade `ruby-openai` 7.4 → 8.x for native Responses API support |

Out of scope for v1: re-searching by corrected text name, saving rarity/prices
onto the product, automatic lookup on upload.

## Architecture

### Gem upgrade

- Bump `ruby-openai` to `~> 8.x`; use `client.responses.create(parameters: …)`.
- Existing users of the gem — `Products::Enrichment::GenerateDraftService` and
  `PurchaseOrders::ReceptionDocumentParserService` — use `client.chat`. Read the
  8.x changelog for breaking changes before bumping; their specs must stay green.
- The upgrade lands in its **own commit** so it can be reverted independently.

### Data: `collectible_ai_lookups`

| Column | Type | Notes |
|---|---|---|
| `user_id` | references, not null | owner; lookups are scoped to their creator |
| `status` | integer enum | `pending`, `running`, `done`, `failed` |
| `result` | jsonb | validated structured answer (new table → jsonb everywhere, no `custom_attributes`-style drift) |
| `error_message` | text | human-readable failure reason |
| `ai_model` | string | model id actually used |
| `tokens_input`, `tokens_output` | integer | from response usage |
| `web_search_calls` | integer | for cost accounting |
| `estimated_cost_cents` | integer | tokens + per-search fee |
| `started_at`, `finished_at` | datetime | stale detection, latency |
| timestamps | | |

`has_one_attached :photo`.

### Units

- **`Collectibles::AiLookup`** (model) — enum, attachment, `stale?`
  (`running`/`pending` for more than 3 minutes), `today_count_for(user)`.
- **`Collectibles::AiLookupService`** — given a lookup: reads the photo bounded
  (downscaled to ~1024px long edge via the existing image processor, never the
  original bytes in memory as base64), builds the Responses request, calls
  OpenAI, validates and returns the parsed result plus usage. Knows nothing about
  HTTP requests or UI.
- **`Collectibles::AiLookupJob`** — status transitions
  (`pending → running → done|failed`), stores result/usage/error. Retries on 429
  with 5 s / 10 s / 20 s backoff like the enrichment job, then `failed`.
  Runs on the Solid Queue worker dyno.
- **`Admin::CollectibleAiLookupsController`** — `create` (multipart photo upload,
  enqueue, return `{ id }`) and `show` (JSON status/result). Admin only.
- **Stimulus `collectible-ai-lookup` controller** — button state, upload via
  `fetch`, polling, form filling, panel rendering.
- **`Collectibles::AiLookupSources`** — the trusted domain constants:
  - `MX`: mercadolibre.com.mx, amazon.com.mx
  - `WORLDWIDE`: ebay.com, amazon.com, amazon.co.jp, hobbydb.com, plazajapan.com, hlj.com

### Request flow

1. Admin chooses photos in "Subir fotos"; the button enables. Click → the
   Stimulus controller POSTs the **first** chosen photo to
   `POST /admin/collectibles/ai_lookups`.
2. Controller validates (image content type, ≤ 15 MB, daily limit), creates the
   lookup with the photo attached, enqueues `AiLookupJob`, returns `{ id }`.
3. Job runs the service: one Responses call with the image input, the
   `web_search` tool restricted to `AiLookupSources` (allowed-domains filter),
   and a strict `json_schema` response format. Request timeout 90 s.
4. Stimulus polls `GET /admin/collectibles/ai_lookups/:id` every ~3 s until
   `done` or `failed` (JSON polling, the pattern that has worked in this app).

## Response schema

All text in Mexican Spanish.

```
identification: { product_name, brand, series, model_code, scale, year_or_edition,
                  confidence (0.0–1.0), notes }
launch_date:    { value: "YYYY-MM-DD" | "YYYY-MM" | "YYYY" | null, source_url }
rarity:         { level: comun | poco_comun | rara | muy_rara | null, reasons: [string] }
prices_mx:      { min, max, currency: "MXN", listings: [ { title, price, url, sold } ] } | null
prices_world:   { min, max, currency: "USD", listings: [ { title, price, url, sold } ] } | null
suggested:      { category, description_es }
warnings:       [string]
```

### Server-side validation (after schema parsing)

- Drop every listing whose URL host is not in `AiLookupSources` for **its**
  market (MX listings must be MX domains, worldwide listings worldwide domains).
- Recompute `min`/`max` from the surviving listings; a market with no surviving
  listings becomes `null`.
- Drop `launch_date.source_url` if not on the allowlist (keep the value, flag a
  warning).
- Cap listings at 5 per market.

## UI on quick_add

- Button **"Identificar con IA"** beside "Subir fotos"; disabled until a photo
  is chosen; disabled with an explanation once the daily limit is reached.
- While running: spinner and "Buscando… (~30–60 s)"; the rest of the form stays usable.
- On `done`, fill **only empty** fields: product name, brand, category,
  description. A field the admin already typed in is left alone; the suggestion
  appears in the panel with a **"Usar"** button. **SKU and prices are never
  auto-filled** (SKU keeps its generator; price is the admin's decision).
- Launch date is shown in the panel; a year-only or year-month value is never
  forced into a date field.
- **AI panel** (card beside the form):
  - identification + confidence; below 0.6 a yellow "verifica el modelo" warning
  - launch date with source link
  - rarity level and reasons
  - two columns, 🇲🇽 MXN and 🌎 USD: range plus up to 5 listings with links,
    each tagged "vendido" or "en venta"; a null market reads
    "Sin datos en sitios confiables"
  - warnings
- On `failed`: panel shows the message and a **"Reintentar"** button; the form is untouched.

## Errors

| Case | Handling |
|---|---|
| OpenAI 429 | Job retries 5 s / 10 s / 20 s, then `failed` with a readable message |
| Timeout | 90 s per call; a lookup `pending`/`running` > 3 min is reported as `failed` by `show` |
| Malformed / off-schema answer | `failed` with reason; raw answer to the Rails log only |
| Non-image or > 15 MB upload | Rejected in `create` before any AI call (422) |
| Daily limit reached | `create` returns 429 with explanation; nothing spent |
| Missing API key | `failed` with "OpenAI no está configurado"; the key is never logged or stored |

## Cost and control

- Each lookup records tokens, web search calls and an estimated cost. Model id
  and prices are constants **verified against current OpenAI docs during
  planning**, not from memory.
- Daily limit constant (default 50 lookups per day, app-wide).
- Admin only; a user can only `show` their own lookups.
- Lookups are kept; the photo attachment is purged 7 days after creation by a
  recurring Solid Queue task.

## Testing (TDD)

- **Service:** stubbed OpenAI responses — complete answer; one market with no
  data; listing URL outside the allowlist dropped and range recomputed;
  malformed JSON; 429 raised.
- **Request specs:** create (valid photo, invalid file type, oversize, daily
  limit, non-admin) and show (own lookup only, stale `running` reported as failed).
- **Job spec:** status transitions; retries exhausted → `failed`.
- **System spec:** choose photo → click → lookup completes (OpenAI stubbed) →
  only empty fields filled, panel shows both markets. CI runs the full system suite.
- **Gem upgrade:** enrichment and reception parser specs green in their own commit.
- No spec calls the real OpenAI API. After deploy, one manual check in production
  with a real photo, asserting behaviour (fields filled, sources open) and never
  printing credentials.
