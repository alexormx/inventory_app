# Collectible AI lookup — accuracy improvements — design

Date: 2026-10-04
Status: approved in conversation, pending written-spec review
Builds on: `docs/superpowers/specs/2026-10-04-collectible-ai-lookup-design.md` (v1, deployed as v799/v800)

## Why

The first production lookup (id 1) identified a piece with confidence 0.8 after
**one** web search, from **one** photo, with search **restricted to the eight
price sites**. The admin then found a more accurate answer with Google Lens.
The model reads the photo, guesses a name, and searches that name as text; a
wrong first guess is never corrected. Google Lens instead matches the image
against its image index.

**Success:** on the admin's real photos, the identified name matches what
Google Lens gives; when the AI is not sure, it says so and offers candidates
instead of filling the form with a wrong model.

## Decisions taken

| Question | Decision |
|---|---|
| Reverse image search | Google Cloud Vision **Web Detection**, first photo only, before the OpenAI call |
| Vision cost control | Hard cap **1,000 Vision calls per calendar month** (= the free tier); over the cap, or on any Vision failure, the lookup continues without it |
| Vision credential | One Google API key restricted to the Vision API, env var `GOOGLE_VISION_API_KEY`, sent in the `X-Goog-Api-Key` header (never in the URL). The human creates and sets it; no agent reads it |
| Vision client | Plain REST via Faraday (already a dependency). No `google-cloud-vision` gem: it pulls gRPC, too heavy for the 512 MB web/worker dynos |
| Admin hints | Optional free-text field "Pistas" (≤ 300 chars), sent to the model as trusted data |
| Photos sent | Up to **3** of the photos the admin picked (e.g. front, base, box), in the order chosen |
| Search scope | Identification may search the **whole web**; prices still come only from the allowlist, enforced server-side as today |
| Verification | Prompt requires at least 2 searches to confirm the identification (max 6) |
| Low confidence | Option **A**: the model returns up to 3 candidates; below confidence 0.7 the form is **not** filled and the panel shows the candidates with "Es esta" buttons |

Out of scope: Vision OCR (`TEXT_DETECTION`) of the base — the admin's hints and a
close-up photo of the base cover it for now; switching to a reasoning model;
SerpApi / Google Lens.

## Changes

### Data (`collectible_ai_lookups`)

- `has_one_attached :photo` → `has_many_attached :photos`. A migration renames
  existing `active_storage_attachments` rows (`record_type =
  'Collectibles::AiLookup'`, `name = 'photo'`) to `name = 'photos'`, so the
  photos of earlier lookups keep working and still get purged.
- New columns: `hints` (text, null), `vision_used` (boolean, default false, not null).
- Validation: 1–3 photos, each in `PHOTO_CONTENT_TYPES` and ≤ 15 MB; `hints` ≤ 300 chars.
- `AiLookup.vision_monthly_cap_reached?` → `where(created_at: Time.current.all_month, vision_used: true).count >= 1000`.
- `AiLookupPhotoPurgeJob` purges `photos` (all of them) after 7 days.

### `Collectibles::ReverseImageSearch` (new, `app/services/collectibles/`)

`ReverseImageSearch.new(jpeg_bytes).call → Hash | nil`

- Returns nil without calling Google when `GOOGLE_VISION_API_KEY` is blank.
- `POST https://vision.googleapis.com/v1/images:annotate`, header
  `X-Goog-Api-Key`, body `{ requests: [{ image: { content: base64 },
  features: [{ type: 'WEB_DETECTION', maxResults: 10 }] }] }`, timeout 15 s.
- Output, trimmed so it cannot bloat the prompt:
  `{ 'best_guesses' => [label…] (≤ 3), 'entities' => [{ 'description', 'score' }] (≤ 8, score desc, blank descriptions dropped),
  'pages' => [{ 'title', 'url' }] (≤ 8, http/https only, titles ≤ 150 chars) }`.
- Any Faraday error, non-2xx, or `error` in the response → logs a warning
  (status and Google's error message only — never the key or headers) and returns nil.

### `AiLookupService`

- Sends up to 3 photos, each downscaled to ≤ 1024 px and stripped as today.
  1024 px is kept on purpose: OpenAI's `high` detail rescales the shortest side
  to 768 px anyway, so a larger upload adds bytes, not legibility. Small base
  text is read better from a close-up photo than from a bigger one.
- Before the OpenAI call, unless `AiLookup.vision_monthly_cap_reached?`:
  runs `ReverseImageSearch` on the first photo's processed JPEG and, as soon as
  Google was actually called (even if it returned nothing useful — that is what
  Google bills), persists `vision_used = true` with `update_column`, so the
  monthly cap counts it even if the OpenAI call fails afterwards.
  `ReverseImageSearch#call` reports whether a request was sent (`called?`).
- The user message includes, when present:
  - `Pistas del admin (tómalas como ciertas salvo que la foto las contradiga claramente): …`
  - `Búsqueda inversa de Google (candidatos a confirmar, pueden estar mal): …` with the trimmed Vision output.
- `web_search` tool **without** `allowed_domains`. Listing URLs are still
  checked with `AiLookupSources.allowed?(url, market)`; anything else is dropped.
- Launch-date `source_url` is kept for any `http(s)` URL (manufacturer sites,
  wikis); the "no es un sitio confiable" warning is removed.
- Prompt: confirm the identification with at least 2 searches (max 6); prices
  only from the listed domains; return `candidates`.
- Result stores `reverse_image` (the trimmed Vision output or null) so the
  panel can show what Google suggested.

### Schema

Add `candidates`: array (≤ 3 kept server-side) of
`{ product_name: string, brand: string|null, model_code: string|null, reason: string, confidence: number }`,
best first. The top-level `identification` stays the best candidate.

### UI on quick_add

- Photo step: a "Pistas (opcional)" text input next to the button, placeholder
  "Marca, texto de la base, número, serie…". The button still appears only
  when at least one photo is chosen.
- The first 3 chosen photos are sent; the status line says "Se enviarán N fotos"
  when more than 3 are chosen ("se usan las primeras 3").
- `identification.confidence ≥ 0.7`: behaviour as today (fill empty fields,
  suggestions with "Usar").
- `< 0.7`: nothing is filled. Panel shows "No estoy seguro; elige la pieza
  correcta" and each candidate (name · brand · code · reason · %) with an
  "Es esta" button. Clicking fills **empty** name and brand from that candidate;
  category and description are filled only when the chosen candidate is the
  top one (the description was written for it).
- When `reverse_image` is present, the panel shows a line "Google sugiere: …"
  with the best guesses, as text.
- All AI and Google text still enters via `textContent`; links only for `http(s)`.

### Errors

| Case | Behaviour |
|---|---|
| Vision key missing / cap reached / Google error | Lookup proceeds without reverse search; `reverse_image` null; no admin-facing error |
| 4+ photos chosen | First 3 sent, status line says so |
| Hints > 300 chars | 422 `"Las pistas no pueden pasar de 300 caracteres."` (input has `maxlength=300` too) |

### Cost

Per lookup: Vision $0 within 1,000/month (hard-capped); OpenAI ~7¢ today →
estimated 12–15¢ with 2–4 searches and up to 3 images. Daily limit (50) unchanged.

## Testing (TDD)

- `ReverseImageSearch`: request shape (header key, no key in URL, feature),
  trimming/limits, non-http page URLs dropped, nil on missing key / 4xx / 5xx /
  timeout, key never in the log line.
- Model: 1–3 photos, hints length, `vision_monthly_cap_reached?`, migration
  rename keeps an existing photo attached.
- Service: sends up to 3 images; hints and Vision text appear in the user
  message; Vision skipped at the cap and when the key is blank; `vision_used`
  set only when Google was called; tool has no `allowed_domains`; launch source
  kept for any https URL; `candidates` trimmed to 3.
- Request: multiple `photos[]` and `hints` accepted; hints too long → 422.
- System: low confidence fills nothing and "Es esta" fills name/brand; hints
  field present; existing specs updated for `photos`.

## Notes for later (not in this change)

- **Product enrichment should also use the photos.** The AI that generates a
  product's description and features (`app/services/products/enrichment/`:
  `BuildContextService`, `BuildPromptService`, `GenerateDraftService`) works
  from text only today. Sending the product/piece photos as image input would
  let it describe what is actually in the box (colors, decorations, variant,
  packaging). Needs its own design: which photos (product vs. piece), how many,
  and cost per enrichment.
- Vision `TEXT_DETECTION` on a base close-up if hints + close-ups prove insufficient.
