# Collectible quick_add — labeled photo slots — design

Date: 2026-10-04
Status: approved in conversation (option A, five slots), pending written-spec review
Builds on: `docs/superpowers/specs/2026-10-04-collectible-ai-accuracy-design.md` (deployed as v802)

## Why

Today the admin picks photos in one multi-file input and a text list asks for
"3/4 view first, then the base, then the box". The order depends on how the
files were selected, so the photo sent to Google (the first) may not be the
3/4 view, and the AI only knows the *usual* order. Labeled slots make the
role of every photo explicit, guarantee the 3/4 view is the one Google sees,
and let the AI read each photo for what it is (e.g. the casting text on the
base).

**Success:** the admin fills labeled boxes; "Identificar con IA" works only
with the 3/4 view; the AI receives every photo with its label; the photos are
still saved on the piece in slot order and, for a new product, also as the
product's photos.

## Decisions taken

| Question | Decision |
|---|---|
| Slots | Five, in this order: **Vista 3/4 elevada** (required for AI), **Base / casting** (recommended), **Lateral**, **Superior**, **Empaque** (optional) |
| Extra photos | A separate "Más fotos de la pieza" input: saved on the piece, **not** sent to the AI |
| AI photo cap | 3 → **5** (one per slot) |
| Google Vision | Always the `three_quarter` photo; legacy lookups without roles use the first photo |
| Missing base | Non-blocking note: "Agrega la foto de la base para que la IA lea el casting." |
| Manual flow | Step stays optional; with no photos nothing changes |
| Product photos | When quick_add **creates a new product**, every uploaded photo (five slots + "Más fotos") is also saved as a **product photo**, same order (3/4 first → primary). With "Usar producto existente" the catalog product's photos are not touched. Photos stay on the piece too |

## Changes

### Data (`collectible_ai_lookups`)

- New column `photo_roles`: `string`, `array: true`, `default: []`, `null: false`.
  `photo_roles[i]` is the role of `ordered_photos[i]`.
- `AiLookup::PHOTO_ROLES` (ordered Hash role → label the AI reads):
  - `three_quarter` → `vista 3/4 elevada de la pieza`
  - `base` → `base de la pieza, donde está el texto del casting (marca, modelo, año, país)`
  - `side` → `vista lateral`
  - `top` → `vista superior`
  - `package` → `empaque (caja, blíster o etiqueta)`
- `MAX_PHOTOS` 3 → 5.
- Validation on create, only when `photo_roles` is present (legacy requests
  send none): every role in `PHOTO_ROLES`, no duplicates, as many roles as
  photos, and `three_quarter` included —
  messages "Los tipos de foto no son válidos." / "Falta la vista 3/4 elevada.".
- `#labeled_photos → [[attachment, role_or_nil], …]` in upload order.

### Endpoint

`POST /admin/collectibles/ai_lookups` accepts `photo_roles[]` alongside
`photos[]` (blank entries dropped). Everything else unchanged.

### `AiLookupService`

- Processes up to 5 photos.
- Content sent to OpenAI: the main text (instructions summary, hints, Google
  suggestions) first, then for each photo an `input_text`
  `"Foto N: <label>"` (`"Foto N (tipo no indicado)"` without a role)
  immediately followed by its `input_image`.
- Prompt step 1 says each photo comes with its type, to read the casting text
  on the base photo and the box text on the package photo; the "usual order"
  sentence goes away.
- Vision runs on the `three_quarter` photo (first photo if no roles).

### UI (step "1. Fotos de la pieza")

- A responsive grid of five boxes (`col-6 col-md-4 col-lg`): dashed border
  (the 3/4 box highlighted), camera icon, title, one-line help. Each box is a
  label for its own hidden `<input type="file" name="inventory[piece_images][]"
  accept="image/*">`, so tapping opens camera/gallery and the form submission
  keeps working unchanged. A chosen photo shows as a thumbnail with "Quitar".
- Below: "Más fotos de la pieza (no se mandan a la IA)" — multiple input with
  the same `name`.
- DOM order (slots, then extras) = the order `piece_images` are attached.
- The ordered-list guide added in v802 is removed (the slot titles replace it).
- AI actions block (hints + button) appears once any slot has a photo.
  Button enabled only with the 3/4 photo; status line:
  - no 3/4: "Agrega la vista 3/4 elevada para identificar con IA."
  - 3/4 without base: "Agrega la foto de la base para que la IA lea el casting."
- `start` sends filled slots in slot order as `photos[]` + `photo_roles[]`.

### Product photos on create (`Collectibles::QuickAddService#attach_images`)

- Each uploaded file is attached to `inventory.piece_images` (as today) and,
  only when this request created the product, also to
  `product.product_images`, in the same order. With no explicit primary, the
  first product photo (the 3/4 view) is the primary (`ordered_product_images`
  sorts by `created_at, id`).
- Each attach creates its **own blob**: deleting a piece photo (allowed on the
  collectible edit page, which purges) must never delete the product's copy,
  and vice versa.
- Storage cost: each photo is stored twice for new products — acceptable at
  quick_add volumes.

## Errors

| Case | Behaviour |
|---|---|
| Roles sent without `three_quarter` (crafted request) | 422 "Falta la vista 3/4 elevada." |
| Unknown / duplicated role, or role count ≠ photo count | 422 "Los tipos de foto no son válidos." |
| 6+ photos | 422 "Máximo 5 fotos por búsqueda." |
| Old page posts `photos[]` without roles | Works as before; labels say "tipo no indicado"; Vision uses the first photo |

## Cost

Two more images at most (~765 tokens each at `high` detail) ≈ +1¢ USD per
lookup. Google stays at one call per lookup.

## Testing (TDD)

- Model: roles validation (valid set, unknown role, duplicate, count mismatch,
  missing 3/4, legacy no-roles), `labeled_photos`, cap 5.
- Request: `photo_roles[]` stored in order; missing 3/4 → 422.
- Service: label `input_text` precedes each image; Vision receives the
  `three_quarter` photo even when it is not first; legacy path unchanged.
- System: five boxes visible; thumbnail + "Quitar"; button disabled with only
  the base, enabled with the 3/4, base note shown; lookup stores roles in slot
  order; submitting the form saves slot photos on the piece in slot order.
- Request (quick_add create): new product → product photos = piece photos in
  the same order, separate blobs, 3/4 is `primary_product_image`; existing
  product → its photos unchanged; no photos → nothing attached.
