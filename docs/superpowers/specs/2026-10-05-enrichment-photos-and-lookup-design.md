# Product enrichment — photos, quick_add identification, fewer inventions — design

Date: 2026-10-05
Status: approved in conversation (B–E, no web search, auto-generate = yes), pending written-spec review
Builds on: identifier scrubbing shipped as v805 (`ScrubIdentifiersService`, prompt v7)

## Why

The description/features generator (`Products::Enrichment::*`, gpt-4o-mini,
text only) reads only catalog text. Products created in quick_add have almost
no text, so drafts are thin or invented — e.g. a published draft calls the
Lamborghini Miura a "superdeportivo japonés". It never sees the photos nor the
quick_add AI identification. Technically: 429s sleep inside the worker thread,
malformed answers are paid for up to 3 times, the recorded cost is inflated
100× (cents converted twice), `confidence_score` is almost always 0.85, and
empty dimensions are sent as `0.0g`.

**Success:** new drafts describe what the photos show and what quick_add
confirmed, without invented origin/history; failures are not paid repeatedly;
the recorded cost is real; quick_add products get a draft automatically, for
review — never auto-published.

## Decisions

| Question | Decision |
|---|---|
| Web search | No |
| Model | `gpt-4o-mini` → **`gpt-4.1-mini`** (pricing page 2026-10-05: $0.40 / $1.60 per 1M in/out; images patch-based ×1.62 ≈ 1,250 tokens for 1024×768 vs ≈ 22,700 on gpt-4o-mini → cheaper with photos, ≈ 0.35¢ per draft with 3 photos) |
| API | Keep Chat Completions (`client.chat`): it accepts images and `json_schema` strict. No Responses API migration |
| Photos | Up to **3**: product catalog photos (`ordered_product_images`, primary first); if none, piece photos of the product's inventories. Downscaled ≤ 1024 px, metadata stripped |
| quick_add identification | `collectible_ai_lookups.product_id` set when quick_add **creates** the product after a `done` lookup by the same admin; the generator receives identification, launch date and rarity as confirmed data |
| Auto-generate | Yes, for products **created** in quick_add. Draft queued after the photo copy (if any), otherwise right away. Never published automatically |
| Confidence | Kept (panel unchanged); concrete `warnings` already shown in the draft view are the signal |

## Changes

### Shared image preparation

New `Images::AiReadyJpeg.call(attachment) → String` (JPEG bytes ≤ 1024 px,
`-strip`, quality 85). Raises `Images::AiReadyJpeg::InvalidImage` for
unreadable files. `Collectibles::AiLookupService#processed_jpeg` uses it
(same behaviour, same error message).

### Link lookup → product

- Migration: `add_reference :collectible_ai_lookups, :product, null: true,
  foreign_key: { on_delete: :nullify }`.
- `AiLookup belongs_to :product, optional: true`; `Product has_many
  :collectible_ai_lookups` (`dependent: :nullify`).
- quick_add form: hidden `ai_lookup_id`, set by the Stimulus controller when a
  lookup finishes (status JSON already carries `id`).
- `QuickAddService`: when it created the product, links
  `AiLookup.where(user: current admin, status: :done).find_by(id: ai_lookup_id)`.
  Someone else's or an unfinished lookup is ignored.

### Generator input (`BuildContextService` / `BuildPromptService`, prompt **v8**)

- Context gains `ai_lookup:` — from the product's latest `done` lookup:
  identification (product_name, brand, series, model_code, scale,
  year_or_edition), `launch_date.value`, `rarity.level` + reasons. No prices,
  no URLs.
- Prompt section `DATOS CONFIRMADOS POR LA IDENTIFICACIÓN CON IA (búsqueda en
  sitios confiables)` when present.
- Dimensions section only when at least one dimension > 0, listing only the
  non-zero ones.
- New system rules:
  - describe only what is in the data or clearly visible in the photos (color,
    decoration, wheels, packaging); if a photo contradicts the data, do not
    choose — add a warning;
  - never state origin, nationality, history, "evolución" or records of a
    vehicle or brand unless the data says so (the model maker's country is
    not the car's);
  - the confirmed-identification section is reliable.

### Generator call (`GenerateDraftService`)

- Model `gpt-4.1-mini`; user message content = prompt text, then for each
  photo a text part `Foto N` and an `image_url` part (`data:image/jpeg;base64,…`,
  `detail: "high"`). A photo that cannot be prepared is skipped with a warning.
- `response_format: { type: "json_schema", json_schema: { name:
  "product_enrichment", strict: true, schema: ResponseSchema.for(template) } }`.
  `attributes` properties = the category template keys, each `string|null`,
  all required, no extra keys; without a template `attributes` is an empty
  object.
- Errors:
  - 429 → `RateLimitError` immediately (no `sleep`); the job retries it.
  - Faraday timeouts / 5xx → `TransientError`; job retries.
  - Invalid JSON / missing or non-natural `description_es` →
    `InvalidResponseError`; job retries **once**.
  - Anything else → `GenerationError`; job does **not** retry.
  - Draft marked `failed` with the message in every case (as today).
- Cost: USD constants `0.40` / `1.60` per 1M; `estimated_cost_cents =
  ((in/1M × 0.40) + (out/1M × 1.60)) × 100`, rounded up.

### Auto-generate

- `GenerateDraftJob.enqueue_for(product)` creates a `queued` draft and enqueues
  it, unless the product already has a `queued`, `generating` or
  `draft_generated` draft. The admin controller's `generate` keeps its current
  behaviour.
- `QuickAddService` (product created, after commit): if photos are copied to
  the product → `CopyPhotosToProductJob`, which calls `enqueue_for` after
  copying; otherwise `enqueue_for` right away.

## Testing (TDD)

- `Images::AiReadyJpeg`: ≤ 1024 px, comment stripped, invalid file raises.
- Link: quick_add with `ai_lookup_id` links on a new product; ignores another
  admin's or a non-done lookup; existing product not linked; system spec: the
  hidden field carries the finished lookup's id.
- Context/prompt: lookup section present with identification/launch/rarity and
  without prices/URLs; zero dimensions omitted; v8 rules present.
- Photo source: product photos first (≤ 3, primary first); piece photos as
  fallback; unreadable photo skipped with warning.
- Generate: model, image parts, strict schema with template keys; error
  classes; no `sleep`; cost value for known usage.
- Job: retry policy per error class (rate limit and transient retried; invalid
  response retried once; generic not retried).
- Auto-generate: new quick_add product → one draft queued (after photo copy
  when photos exist); existing product → none; no duplicate pending drafts.
