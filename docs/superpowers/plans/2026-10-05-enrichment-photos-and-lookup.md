# Enrichment Photos & Lookup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Product description/feature drafts use up to 3 photos and the quick_add AI identification, follow stricter no-invention rules with a strict JSON schema on gpt-4.1-mini, fail cheaply, record the real cost, and are queued automatically for products created in quick_add.

**Architecture:** A shared `Images::AiReadyJpeg` prepares photos for both AI features. `collectible_ai_lookups.product_id` links a quick_add identification to the product it created; `BuildContextService` reads it and `BuildPromptService` (v8) renders it. `GenerateDraftService` keeps Chat Completions but sends image parts and a strict schema from `ResponseSchema.for(template)`, maps failures to error classes that `GenerateDraftJob` retries differently. `GenerateDraftJob.enqueue_for` is called by quick_add (directly or after `CopyPhotosToProductJob`).

**Tech Stack:** Rails 8.0.1, PostgreSQL, ActiveStorage + `image_processing` (MiniMagick), `ruby-openai` 8.3 (`client.chat`), Solid Queue, Stimulus (esbuild), RSpec + Capybara.

**Spec:** `docs/superpowers/specs/2026-10-05-enrichment-photos-and-lookup-design.md`

## Global Constraints

- Ruby commands run as `~/.rvm/bin/rvm 3.2.3 do <cmd>`. Test DB: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bin/rails db:test:prepare`; never destructive tasks against `inventory_app_development`; `bin/rails db:migrate` (development) allowed.
- System specs need `RUN_SYSTEM_SPECS=1`; run `npm run build` after Stimulus changes.
- Model `gpt-4.1-mini`; cost constants USD `0.40` input / `1.60` output per 1M tokens (pricing page verified 2026-10-05).
- Photos: max **3**, ≤ 1024 px, metadata stripped; product catalog photos first, piece photos as fallback.
- No web search. No spec calls OpenAI for real. Never print `OPENAI_API_KEY`.
- A draft is never published automatically.
- Spec traps: `create(:product)` already has catalog photos (purge them when a test needs none); `test1.png`/`test2.png` are identical; quick_add requests need `product[selling_price]` and `product[brand]`.
- After code changes run `graphify update .`.

## Review Focus

1. **quick_add product created with photos** — the draft must be generated after the photo copy, so it sees the photos; exactly one draft. → Task 5 job spec + request spec.
2. **Lookup ids from another admin or an unfinished lookup posted in the form** — must not be linked. → Task 2 request spec.
3. **A product photo that is not an image** — the draft is still generated, with a warning. → Task 3 photo source spec + Task 4 generate spec.
4. **OpenAI answers malformed JSON twice** — paid at most twice, then the draft stays `failed`. → Task 4 job spec.
5. **Existing specs that run jobs inline (system 'alta', quick_add photos request spec)** — must not reach OpenAI. → Task 5 edits.

---

### Task 1: Shared AI-ready JPEG

**Files:**
- Create: `app/services/images/ai_ready_jpeg.rb`, `spec/services/images/ai_ready_jpeg_spec.rb`
- Modify: `app/services/collectibles/ai_lookup_service.rb` (`IMAGE_MAX_EDGE`, `processed_jpeg`)

**Interfaces:**
- Produces: `Images::AiReadyJpeg.call(attachment) → String` (JPEG bytes); `Images::AiReadyJpeg::InvalidImage < StandardError`; `Images::AiReadyJpeg::MAX_EDGE = 1024`.

- [ ] **Step 1: Failing spec** — `spec/services/images/ai_ready_jpeg_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Images::AiReadyJpeg do
  let(:product) { create(:product, skip_seed_inventory: true).tap { |p| p.product_images.purge } }

  def attach(io, filename)
    product.product_images.attach(io: io, filename: filename, content_type: 'image/jpeg')
    product.product_images.attachments.max_by(&:id)
  end

  it 'reduce a 1024 px, convierte a JPEG y quita metadatos' do
    Tempfile.create(['big', '.png']) do |big|
      system('convert', '-size', '3000x2000', 'xc:red', '-set', 'comment', 'GPS 19.43,-99.13', big.path, exception: true)
      image = MiniMagick::Image.read(described_class.call(attach(File.open(big.path), 'big.png')))
      expect([image.width, image.height].max).to be <= 1024
      expect(image.type).to eq('JPEG')
      expect(image['%c'].to_s).not_to include('GPS')
    end
  end

  it 'falla con InvalidImage si el archivo no es imagen' do
    attachment = attach(StringIO.new('no soy imagen'), 'falsa.jpg')
    expect { described_class.call(attachment) }.to raise_error(described_class::InvalidImage)
  end
end
```
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/images/ai_ready_jpeg_spec.rb` — Expected: FAIL `uninitialized constant Images`.

- [ ] **Step 2: Implementation** — `app/services/images/ai_ready_jpeg.rb`:
```ruby
# frozen_string_literal: true

module Images
  # Prepara una foto para mandarla a un modelo de IA: lado mayor ≤ 1024 px,
  # JPEG y sin metadatos (`-strip` quita EXIF/GPS y comentarios). Lo usan la
  # identificación de quick_add y la generación de descripciones.
  module AiReadyJpeg
    class InvalidImage < StandardError; end

    MAX_EDGE = 1024

    module_function

    def call(attachment)
      attachment.blob.open do |file|
        resized = ImageProcessing::MiniMagick.source(file.path)
                                             .resize_to_limit(MAX_EDGE, MAX_EDGE)
                                             .strip
                                             .convert('jpg')
                                             .saver(quality: 85)
                                             .call
        begin
          File.binread(resized.path)
        ensure
          resized.close!
        end
      end
    rescue MiniMagick::Error, ImageProcessing::Error => e
      raise InvalidImage, e.message.lines.first.to_s.strip
    end
  end
end
```
In `app/services/collectibles/ai_lookup_service.rb`: `IMAGE_MAX_EDGE = 1024` → `IMAGE_MAX_EDGE = Images::AiReadyJpeg::MAX_EDGE`, and replace the whole `processed_jpeg` method with:
```ruby
    def processed_jpeg(photo)
      Images::AiReadyJpeg.call(photo)
    rescue Images::AiReadyJpeg::InvalidImage => e
      raise Error, "La foto #{photo.filename} no es una imagen válida: #{e.message}"
    end
```
Also delete the comment block right above `processed_photos` that describes the resize/strip details only if it now refers to code that moved; keep the "1024 px basta…" sentence.

- [ ] **Step 3: Run + commit**
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/images spec/services/collectibles` — Expected: 0 failures.
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/services/images app/services/collectibles/ai_lookup_service.rb`
```bash
git add app/services/images spec/services/images app/services/collectibles/ai_lookup_service.rb
git commit -m "refactor: preparación compartida de fotos para la IA"
```

---

### Task 2: Link the quick_add identification to the product it created

**Files:**
- Create: `db/migrate/20261005120000_add_product_to_collectible_ai_lookups.rb`, `spec/requests/admin/collectibles_quick_add_enrichment_spec.rb`
- Modify: `db/schema.rb`, `app/models/collectibles/ai_lookup.rb`, `app/models/product.rb`, `app/services/collectibles/quick_add_service.rb`, `app/controllers/admin/collectibles_controller.rb` (`collectible_params`), `app/views/admin/collectibles/quick_add.html.erb`, `app/javascript/controllers/collectible_ai_lookup_controller.js`, `spec/system/admin/collectible_ai_lookup_spec.rb`

**Interfaces:**
- Produces: `AiLookup#product` (optional), `Product#collectible_ai_lookups`; form param `ai_lookup_id`; Stimulus target `lookupId`.

- [ ] **Step 1: Failing request spec** — `spec/requests/admin/collectibles_quick_add_enrichment_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin quick_add liga la identificación con IA', type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  def lookup_for(user, status: :done)
    Collectibles::AiLookup.new(user: user).tap do |l|
      l.photos.attach(io: File.open(Rails.root.join('spec/fixtures/files/test1.png')), filename: 'a.png', content_type: 'image/png')
      l.save!
      l.update!(status: status, result: { 'identification' => { 'brand' => 'Tomica' } })
    end
  end

  def quick_add(extra = {})
    post admin_collectibles_quick_add_path, params: {
      use_existing_product: '0',
      product: { product_name: 'Pieza IA', category: 'Autos a escala', brand: 'Tomica', selling_price: '250' },
      inventory: { item_condition: 'loose' }
    }.merge(extra)
  end

  it 'liga la búsqueda terminada del mismo admin al producto nuevo' do
    lookup = lookup_for(admin)
    quick_add(ai_lookup_id: lookup.id)
    expect(lookup.reload.product).to eq(Product.order(:id).last)
  end

  it 'ignora la búsqueda de otro admin' do
    lookup = lookup_for(create(:user, :admin))
    quick_add(ai_lookup_id: lookup.id)
    expect(lookup.reload.product).to be_nil
  end

  it 'ignora una búsqueda que no terminó' do
    lookup = lookup_for(admin, status: :running)
    quick_add(ai_lookup_id: lookup.id)
    expect(lookup.reload.product).to be_nil
  end

  it 'no liga nada a un producto existente' do
    lookup = lookup_for(admin)
    product = create(:product)
    post admin_collectibles_quick_add_path, params: {
      use_existing_product: '1', existing_product_id: product.id, ai_lookup_id: lookup.id,
      inventory: { item_condition: 'loose' }
    }
    expect(lookup.reload.product).to be_nil
  end
end
```
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/requests/admin/collectibles_quick_add_enrichment_spec.rb` — Expected: FAIL `undefined method 'product'`.

- [ ] **Step 2: Migration + models**
`db/migrate/20261005120000_add_product_to_collectible_ai_lookups.rb`:
```ruby
# frozen_string_literal: true

class AddProductToCollectibleAiLookups < ActiveRecord::Migration[8.0]
  def change
    add_reference :collectible_ai_lookups, :product, null: true, foreign_key: { on_delete: :nullify }
  end
end
```
Run: `~/.rvm/bin/rvm 3.2.3 do bin/rails db:migrate && RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bin/rails db:test:prepare`

`app/models/collectibles/ai_lookup.rb`: below `belongs_to :user` add
```ruby
    # El producto que se dio de alta con esta identificación (quick_add); su
    # descripción con IA usa estos datos como confirmados.
    belongs_to :product, optional: true
```
`app/models/product.rb`: next to `has_many :inventories …` add
```ruby
  has_many :collectible_ai_lookups, class_name: 'Collectibles::AiLookup', dependent: :nullify
```

- [ ] **Step 3: Service + controller**
`app/controllers/admin/collectibles_controller.rb` `collectible_params`: add `:ai_lookup_id,` right after `:existing_product_id,`.

`app/services/collectibles/quick_add_service.rb`: in `call`, change
```ruby
        attach_images if @errors.empty? && @inventory&.persisted?
```
to
```ruby
        attach_images if @errors.empty? && @inventory&.persisted?
        link_ai_lookup if @errors.empty?
```
and add before `def update_product_stats`:
```ruby
    # Si el admin identificó la pieza con IA antes de dar de alta un producto
    # nuevo, la búsqueda queda ligada a él: la descripción con IA la usa como
    # datos confirmados. Sólo una búsqueda terminada y del mismo admin.
    def link_ai_lookup
      return unless @product_created && @params[:ai_lookup_id].present?

      Collectibles::AiLookup.where(user: @user, status: :done)
                            .find_by(id: @params[:ai_lookup_id])
                            &.update!(product: @product)
    end

```

- [ ] **Step 4: View + JS**
`app/views/admin/collectibles/quick_add.html.erb`: right after the panel line `<div class="card mb-4 d-none border-info" data-collectible-ai-lookup-target="panel" aria-live="polite"></div>` add:
```erb
  <%# La búsqueda con IA que se usó; el alta la liga al producto nuevo. %>
  <%= hidden_field_tag :ai_lookup_id, nil, id: 'ai_lookup_id', data: { collectible_ai_lookup_target: 'lookupId' } %>
```
`app/javascript/controllers/collectible_ai_lookup_controller.js`:
- `static targets = ["slot", "button", "status", "panel", "actions", "hints"]` → `static targets = ["slot", "button", "status", "panel", "actions", "hints", "lookupId"]`
- in `start()`, right after `this.hidePanel()` add `if (this.hasLookupIdTarget) this.lookupIdTarget.value = ""`
- `if (state.status === "done") this.finish(state.result)` → `if (state.status === "done") this.finish(state.result, state.id)`
- `finish(result) {` → `finish(result, lookupId) {` and as its second line (after `this.stopPolling()`) add `if (this.hasLookupIdTarget) this.lookupIdTarget.value = lookupId ?? ""`

`spec/system/admin/collectible_ai_lookup_spec.rb`, in `'llena sólo los campos vacíos y enseña rareza y precios por mercado'`, after the `have_css(... 'Poco común', wait: 15)` line add:
```ruby
    expect(find('#ai_lookup_id', visible: false).value).to eq(Collectibles::AiLookup.last.id.to_s)
```

- [ ] **Step 5: Run + commit**
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/requests/admin/collectibles_quick_add_enrichment_spec.rb spec/requests/admin/collectibles_quick_add_photos_spec.rb spec/models/collectibles` — Expected: 0 failures.
Run: `npm run build && RUN_SYSTEM_SPECS=1 RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/system/admin/collectible_ai_lookup_spec.rb` — Expected: 0 failures.
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/models app/services/collectibles app/controllers/admin/collectibles_controller.rb db/migrate/20261005120000_add_product_to_collectible_ai_lookups.rb`
```bash
git add db/migrate/20261005120000_add_product_to_collectible_ai_lookups.rb db/schema.rb app/models/collectibles/ai_lookup.rb app/models/product.rb app/services/collectibles/quick_add_service.rb app/controllers/admin/collectibles_controller.rb app/views/admin/collectibles/quick_add.html.erb app/javascript/controllers/collectible_ai_lookup_controller.js spec/requests/admin/collectibles_quick_add_enrichment_spec.rb spec/system/admin/collectible_ai_lookup_spec.rb
git commit -m "feat: la identificación de quick_add queda ligada al producto nuevo"
```

---

### Task 3: Generator inputs — photos, confirmed identification, prompt v8

**Files:**
- Create: `app/services/products/enrichment/photo_source_service.rb`, `spec/services/products/enrichment/photo_source_service_spec.rb`
- Modify: `app/services/products/enrichment/build_context_service.rb`, `app/services/products/enrichment/build_prompt_service.rb`, `spec/services/products/enrichment/build_context_service_spec.rb`, `spec/services/products/enrichment/build_prompt_service_spec.rb`, `spec/services/products/enrichment/generate_draft_service_spec.rb` (version string)

**Interfaces:**
- Consumes: `Images::AiReadyJpeg`, `Product#collectible_ai_lookups`.
- Produces: `PhotoSourceService.new(product).call → Result(jpegs: [String], warnings: [String])`; context key `:ai_lookup` (`{ identification: Hash, launch_date: String|nil, rarity_level: String|nil, rarity_reasons: [String] }` or nil); `PROMPT_VERSION = "v8"`.

- [ ] **Step 1: Failing specs**

`spec/services/products/enrichment/photo_source_service_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Products::Enrichment::PhotoSourceService do
  let(:product) { create(:product, skip_seed_inventory: true).tap { |p| p.product_images.purge } }

  def png(color)
    Tempfile.create(['p', '.png']).tap { |f| system('convert', '-size', '20x20', "xc:#{color}", f.path, exception: true) }
  end

  it 'usa hasta 3 fotos del producto, la principal primero' do
    %w[red blue green yellow].each_with_index do |color, i|
      product.product_images.attach(io: File.open(png(color).path), filename: "p#{i}.png", content_type: 'image/png')
    end
    product.set_primary_product_image!(product.product_images.attachments.max_by(&:id).id)

    result = described_class.new(product.reload).call
    expect(result.jpegs.size).to eq(3)
    # El procesamiento es determinista: la primera foto enviada es la principal.
    expect(result.jpegs.first).to eq(Images::AiReadyJpeg.call(product.primary_product_image))
    expect(result.warnings).to be_empty
  end

  it 'sin fotos de producto usa las de sus piezas' do
    inventory = create(:inventory, product: product, item_condition: :loose)
    inventory.piece_images.attach(io: File.open(png('red').path), filename: 'pieza.png', content_type: 'image/png')
    expect(described_class.new(product.reload).call.jpegs.size).to eq(1)
  end

  it 'omite una foto ilegible y lo avisa' do
    product.product_images.attach(io: StringIO.new('no soy imagen'), filename: 'falsa.png', content_type: 'image/png')
    product.product_images.attach(io: File.open(png('red').path), filename: 'buena.png', content_type: 'image/png')
    result = described_class.new(product.reload).call
    expect(result.jpegs.size).to eq(1)
    expect(result.warnings.join).to include('falsa.png')
  end

  it 'sin fotos regresa vacío' do
    expect(described_class.new(product).call.jpegs).to eq([])
  end
end
```

In `spec/services/products/enrichment/build_context_service_spec.rb` append before the final `end`:
```ruby
  describe "identificación de quick_add" do
    def lookup_for(prod, status:, result:)
      Collectibles::AiLookup.new(user: create(:user, :admin)).tap do |l|
        l.photos.attach(io: File.open(Rails.root.join("spec/fixtures/files/test1.png")), filename: "a.png", content_type: "image/png")
        l.save!
        l.update!(status: status, product: prod, result: result)
      end
    end

    let(:lookup_result) do
      {
        "identification" => { "product_name" => "Tomica No. 23 Skyline", "brand" => "Tomica", "series" => "Regular",
                              "model_code" => "No. 23", "scale" => "1/62", "year_or_edition" => "2019", "confidence" => 0.9, "notes" => "x" },
        "launch_date" => { "value" => "2019-06", "source_url" => "https://www.hobbydb.com/x" },
        "rarity" => { "level" => "poco_comun", "reasons" => ["Descontinuado"] },
        "prices_mx" => { "min" => 1, "max" => 2, "listings" => [] }
      }
    end

    it "incluye identificación, lanzamiento y rareza de la búsqueda terminada, sin precios ni URLs" do
      lookup_for(product, status: :done, result: lookup_result)
      ai = described_class.new(product.reload).call[:ai_lookup]

      expect(ai[:identification]).to eq("product_name" => "Tomica No. 23 Skyline", "brand" => "Tomica", "series" => "Regular",
                                         "model_code" => "No. 23", "scale" => "1/62", "year_or_edition" => "2019")
      expect(ai[:launch_date]).to eq("2019-06")
      expect(ai[:rarity_level]).to eq("poco_comun")
      expect(ai[:rarity_reasons]).to eq(["Descontinuado"])
      expect(ai.to_s).not_to include("hobbydb").and not_to include("listings")
    end

    it "ignora búsquedas que no terminaron" do
      lookup_for(product, status: :failed, result: lookup_result)
      expect(described_class.new(product.reload).call[:ai_lookup]).to be_nil
    end
  end
```

In `spec/services/products/enrichment/build_prompt_service_spec.rb`:
- `it "uses prompt version v7"` → `"uses prompt version v8"` with `eq("v8")`.
- append before the final `end`:
```ruby
  describe "v8" do
    it "prohíbe inventar origen, nacionalidad o historia y pide describir sólo lo visible" do
      system = result[:system]
      expect(system).to include("nacionalidad")
      expect(system).to include("visible con certeza en las fotos")
    end

    it "incluye los datos confirmados por la identificación con IA" do
      context[:ai_lookup] = { identification: { "brand" => "Tomica", "model_code" => "No. 23", "scale" => "1/62" },
                              launch_date: "2019-06", rarity_level: "poco_comun", rarity_reasons: ["Descontinuado"] }
      user = result[:user]
      expect(user).to include("DATOS CONFIRMADOS POR LA IDENTIFICACIÓN CON IA")
      expect(user).to include("- Código del fabricante: No. 23")
      expect(user).to include("- Fecha de lanzamiento: 2019-06")
      expect(user).to include("- Rareza: poco común (Descontinuado)")
    end

    it "omite las dimensiones en cero" do
      context[:dimensions] = { weight_gr: 0.0, length_cm: 16.0, width_cm: 0.0, height_cm: 0.0 }
      user = result[:user]
      expect(user).to include("Largo: 16.0cm")
      expect(user).not_to include("Peso")
      expect(user).not_to include("0.0g")
    end

    it "sin dimensiones no manda la sección" do
      context[:dimensions] = { weight_gr: 0.0, length_cm: 0.0, width_cm: 0.0, height_cm: 0.0 }
      expect(result[:user]).not_to include("DIMENSIONES DEL EMPAQUE")
    end
  end
```
In `spec/services/products/enrichment/generate_draft_service_spec.rb`: `eq("v7")` → `eq("v8")`.

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/products/enrichment` — Expected: FAIL (missing `PhotoSourceService`, `:ai_lookup`, v8 rules, dimensions format).

- [ ] **Step 2: PhotoSourceService** — `app/services/products/enrichment/photo_source_service.rb`:
```ruby
# frozen_string_literal: true

module Products
  module Enrichment
    # Las fotos que ve la IA al describir un producto: hasta 3 de catálogo (la
    # principal primero) o, si no tiene, las de sus piezas en inventario. Una
    # foto ilegible se omite con aviso; la descripción se genera igual.
    class PhotoSourceService
      MAX_PHOTOS = 3
      Result = Struct.new(:jpegs, :warnings, keyword_init: true)

      def initialize(product)
        @product = product
      end

      def call
        jpegs = []
        warnings = []
        attachments.first(MAX_PHOTOS).each do |attachment|
          jpegs << Images::AiReadyJpeg.call(attachment)
        rescue Images::AiReadyJpeg::InvalidImage
          warnings << "No se pudo leer la foto #{attachment.filename}; se generó sin ella."
        end
        Result.new(jpegs: jpegs, warnings: warnings)
      end

      private

      def attachments
        catalog = @product.ordered_product_images
        return catalog if catalog.any?

        @product.inventories.order(:id).flat_map { |inventory| inventory.piece_images.attachments.sort_by(&:id) }
      end
    end
  end
end
```

- [ ] **Step 3: Context** — in `app/services/products/enrichment/build_context_service.rb`, add `ai_lookup:         build_ai_lookup_context,` after `supplier_context:  build_supplier_context,`, and add before `def build_supplier_context`:
```ruby
      # La identificación de quick_add ligada a este producto (la más reciente
      # que terminó). Sólo identificación, lanzamiento y rareza: los precios y
      # las URLs no le sirven a la descripción.
      def build_ai_lookup_context
        result = @product.collectible_ai_lookups.done.order(created_at: :desc).first&.result
        return nil unless result.is_a?(Hash)

        identification = result['identification'].is_a?(Hash) ? result['identification'] : {}
        {
          identification: identification.slice(*%w[product_name brand series model_code scale year_or_edition]).compact_blank,
          launch_date: result.dig('launch_date', 'value'),
          rarity_level: result.dig('rarity', 'level'),
          rarity_reasons: Array(result.dig('rarity', 'reasons'))
        }
      end

```

- [ ] **Step 4: Prompt v8** — in `app/services/products/enrichment/build_prompt_service.rb`:

4a. `PROMPT_VERSION = "v7"` → `"v8"`; below `INTERNAL_KEY = …` add:
```ruby
      AI_LOOKUP_LABELS = {
        "product_name" => "Pieza identificada", "brand" => "Marca", "series" => "Serie",
        "model_code" => "Código del fabricante", "scale" => "Escala", "year_or_edition" => "Año o edición"
      }.freeze
      RARITY_LABELS = { "comun" => "común", "poco_comun" => "poco común", "rara" => "rara", "muy_rara" => "muy rara" }.freeze
      DIMENSION_LABELS = { weight_gr: ["Peso", "g"], length_cm: ["Largo", "cm"], width_cm: ["Ancho", "cm"], height_cm: ["Alto", "cm"] }.freeze
```

4b. In `SYSTEM_PROMPT`, after rule 20 add:
```
        21. Si se incluyen fotos, describe sólo lo que sea visible con certeza en las fotos (color, decoración, rines, empaque). Si una foto contradice los datos, no elijas: avisa en `warnings`.
        22. NUNCA afirmes origen, nacionalidad, historia, "evolución" o récords de un vehículo o de una marca si no vienen en los datos. El país del fabricante del modelo a escala no es el del auto real (un Lamborghini de Tomica sigue siendo un auto italiano).
        23. Los DATOS CONFIRMADOS POR LA IDENTIFICACIÓN CON IA vienen de una búsqueda en sitios confiables: úsalos como ciertos.
```

4c. Replace the dimensions block
```ruby
        if @context[:dimensions].present?
          dims = @context[:dimensions]
          parts << "\nDIMENSIONES DEL EMPAQUE:"
          parts << "  - Peso: #{dims[:weight_gr]}g"
          parts << "  - Largo: #{dims[:length_cm]}cm x Ancho: #{dims[:width_cm]}cm x Alto: #{dims[:height_cm]}cm"
        end
```
with
```ruby
        # Sólo las medidas que existen: "Peso: 0.0g" confundía a la IA.
        dims = (@context[:dimensions] || {}).select { |key, value| DIMENSION_LABELS.key?(key) && value.to_f.positive? }
        if dims.any?
          parts << "\nDIMENSIONES DEL EMPAQUE:"
          dims.each do |key, value|
            label, unit = DIMENSION_LABELS.fetch(key)
            parts << "  - #{label}: #{value}#{unit}"
          end
        end
```

4d. Replace `parts << build_supplier_catalog_section` with
```ruby
        parts << build_ai_lookup_section
        parts << build_supplier_catalog_section
```
and add before `def build_supplier_catalog_section`:
```ruby
      def build_ai_lookup_section
        lookup = @context[:ai_lookup]
        return nil if lookup.blank?

        lines = ["\nDATOS CONFIRMADOS POR LA IDENTIFICACIÓN CON IA (búsqueda en sitios confiables):"]
        lookup[:identification].to_h.each { |key, value| lines << "- #{AI_LOOKUP_LABELS.fetch(key, key)}: #{value}" }
        lines << "- Fecha de lanzamiento: #{lookup[:launch_date]}" if lookup[:launch_date].present?
        if lookup[:rarity_level].present?
          reasons = Array(lookup[:rarity_reasons]).join("; ")
          lines << "- Rareza: #{RARITY_LABELS.fetch(lookup[:rarity_level], lookup[:rarity_level])}#{" (#{reasons})" if reasons.present?}"
        end
        lines.join("\n")
      end

```

- [ ] **Step 5: Run + commit**
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/products/enrichment spec/services/images` — Expected: 0 failures.
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/services/products/enrichment`
```bash
git add app/services/products/enrichment spec/services/products/enrichment
git commit -m "feat: la descripción con IA recibe fotos e identificación de quick_add (prompt v8)"
```

---

### Task 4: gpt-4.1-mini call with photos, strict schema, error classes, real cost

**Files:**
- Create: `app/services/products/enrichment/response_schema.rb`, `spec/jobs/products/enrichment/generate_draft_job_spec.rb`
- Modify: `app/services/products/enrichment/generate_draft_service.rb`, `app/jobs/products/enrichment/generate_draft_job.rb`, `spec/services/products/enrichment/generate_draft_service_spec.rb`

**Interfaces:**
- Consumes: `PhotoSourceService` (Task 3).
- Produces: `ResponseSchema.for(template) → Hash`; errors `GenerationError`, `RateLimitError`, `TransientError`, `InvalidResponseError` (all `< GenerationError`); `GenerateDraftService::DEFAULT_MODEL = "gpt-4.1-mini"`; `GenerateDraftJob.enqueue_for(product)`.

- [ ] **Step 1: Failing specs**

In `spec/services/products/enrichment/generate_draft_service_spec.rb`:

(a) Replace the example `"calls OpenAI with correct parameters"` with:
```ruby
    it "calls OpenAI with gpt-4.1-mini and a strict schema built from the template" do
      service.call
      expect(openai_client).to have_received(:chat) do |parameters:|
        expect(parameters[:model]).to eq("gpt-4.1-mini")
        format = parameters[:response_format]
        expect(format[:type]).to eq("json_schema")
        expect(format.dig(:json_schema, :strict)).to be(true)
        attributes = format.dig(:json_schema, :schema, :properties, :attributes)
        expect(attributes[:required]).to eq(template.attribute_keys)
        expect(attributes[:additionalProperties]).to be(false)
      end
    end

    it "manda las fotos del producto como imágenes" do
      service.call
      expect(openai_client).to have_received(:chat) do |parameters:|
        content = parameters[:messages].last[:content]
        images = content.select { |part| part[:type] == "image_url" }
        expect(images).not_to be_empty
        expect(images.first.dig(:image_url, :url)).to start_with("data:image/jpeg;base64,")
      end
    end
```
(b) Replace the example `"estimates cost"` with:
```ruby
    it "estimates the real cost in cents with gpt-4.1-mini prices" do
      openai_response["usage"] = { "prompt_tokens" => 1_000_000, "completion_tokens" => 500_000 }
      service.call
      # 1M × $0.40 + 0.5M × $1.60 = $1.20 → 120 centavos
      expect(draft.reload.estimated_cost_cents).to eq(120)
    end
```
(c) Replace the whole `context "when OpenAI returns 429 rate limit"` block with:
```ruby
    context "when OpenAI returns 429 rate limit" do
      before do
        allow(openai_client).to receive(:chat).and_raise(Faraday::TooManyRequestsError.new(status: 429))
      end

      it "raises RateLimitError right away without sleeping the worker" do
        expect(service).not_to receive(:sleep)
        expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::RateLimitError)
        expect(openai_client).to have_received(:chat).once
        expect(draft.reload.status).to eq("failed")
      end
    end
```
(d) In `context "when OpenAI client raises an error"` change the expectation class to `Products::Enrichment::GenerateDraftService::TransientError` and the title to `"marks draft as failed and raises TransientError"`.
(e) Append before the final `end`:
```ruby
  describe "clasificación de errores" do
    it "una respuesta que no es JSON es InvalidResponseError" do
      openai_response["choices"][0]["message"]["content"] = "{roto"
      expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::InvalidResponseError)
    end

    it "un error inesperado es GenerationError genérico (no se reintenta)" do
      allow(openai_client).to receive(:chat).and_raise(NoMethodError, "boom")
      expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::GenerationError) { |e|
        expect(e).not_to be_a(Products::Enrichment::GenerateDraftService::InvalidResponseError)
        expect(e).not_to be_a(Products::Enrichment::GenerateDraftService::TransientError)
      }
    end
  end

  describe "fotos ilegibles" do
    it "genera igual y lo avisa" do
      product.product_images.purge
      product.product_images.attach(io: StringIO.new("no soy imagen"), filename: "falsa.png", content_type: "image/png")
      service.call
      expect(draft.reload.status).to eq("draft_generated")
      expect(draft.warnings.join).to include("falsa.png")
    end
  end
```

`spec/jobs/products/enrichment/generate_draft_job_spec.rb`:
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::Enrichment::GenerateDraftJob do
  include ActiveJob::TestHelper

  let(:errors) { Products::Enrichment::GenerateDraftService }
  let(:product) { create(:product, skip_seed_inventory: true) }
  let(:draft) { create(:product_description_draft, product: product, status: :queued) }
  let(:service) { instance_double(Products::Enrichment::GenerateDraftService) }

  before { allow(Products::Enrichment::GenerateDraftService).to receive(:new).and_return(service) }

  def run_failing_with(error)
    allow(service).to receive(:call).and_raise(error)
    perform_enqueued_jobs { described_class.perform_later(draft.id) }
  rescue errors::GenerationError
    nil
  end

  it "reintenta una respuesta mal formada sólo una vez" do
    run_failing_with(errors::InvalidResponseError.new("roto"))
    expect(service).to have_received(:call).twice
  end

  it "reintenta un tropiezo de red hasta 3 veces" do
    run_failing_with(errors::TransientError.new("timeout"))
    expect(service).to have_received(:call).exactly(3).times
  end

  it "reintenta la saturación (429) hasta 5 veces" do
    run_failing_with(errors::RateLimitError.new("429"))
    expect(service).to have_received(:call).exactly(5).times
  end

  it "no reintenta un error inesperado" do
    run_failing_with(errors::GenerationError.new("boom"))
    expect(service).to have_received(:call).once
  end

  describe ".enqueue_for" do
    it "crea un borrador en cola y lo encola" do
      expect { described_class.enqueue_for(product) }.to have_enqueued_job(described_class)
      expect(product.description_drafts.queued.count).to eq(1)
    end

    it "no duplica si ya hay un borrador pendiente" do
      create(:product_description_draft, product: product, status: :draft_generated)
      expect { described_class.enqueue_for(product) }.not_to have_enqueued_job(described_class)
    end
  end
end
```
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/products/enrichment/generate_draft_service_spec.rb spec/jobs/products/enrichment` — Expected: FAIL (model, schema, images, cost 120, missing error classes and `enqueue_for`).

- [ ] **Step 2: ResponseSchema** — `app/services/products/enrichment/response_schema.rb`:
```ruby
# frozen_string_literal: true

module Products
  module Enrichment
    # Esquema estricto (Structured Outputs) de la respuesta. Los atributos son
    # las llaves de la plantilla de la categoría (texto o null, todas presentes,
    # ninguna extra); sin plantilla, `attributes` es un objeto vacío.
    module ResponseSchema
      NULLABLE_STRING = { type: %w[string null] }.freeze
      STRING_LIST = { type: "array", items: { type: "string" } }.freeze

      module_function

      def for(template)
        keys = template ? template.attribute_keys : []
        {
          type: "object", additionalProperties: false,
          required: %w[product_name description_es highlights attributes seo_keywords warnings confidence_score],
          properties: {
            product_name: { type: "string" },
            description_es: { type: "string" },
            highlights: STRING_LIST,
            attributes: { type: "object", additionalProperties: false, required: keys,
                          properties: keys.index_with { NULLABLE_STRING } },
            seo_keywords: STRING_LIST,
            warnings: STRING_LIST,
            confidence_score: { type: "number" }
          }
        }
      end
    end
  end
end
```

- [ ] **Step 3: GenerateDraftService** — in `app/services/products/enrichment/generate_draft_service.rb`:

3a. Replace
```ruby
      class GenerationError < StandardError; end
      class RateLimitError < GenerationError; end
```
with
```ruby
      class GenerationError < StandardError; end
      # 429: el job reintenta con espera, sin dormir el hilo del worker.
      class RateLimitError < GenerationError; end
      # Timeout, conexión o 5xx: el job reintenta.
      class TransientError < GenerationError; end
      # JSON roto o descripción que no pasa las reglas: el job reintenta una vez.
      class InvalidResponseError < GenerationError; end
```

3b. Replace the block from `DEFAULT_MODEL = "gpt-4o-mini"` through `COST_OUTPUT_PER_M = 60   # $0.60 / 1M output tokens → 60 cents` with:
```ruby
      DEFAULT_MODEL = "gpt-4.1-mini"
      REQUEST_TIMEOUT = 90

      # USD por 1M tokens, gpt-4.1-mini, página de precios de OpenAI verificada el 2026-10-05.
      COST_INPUT_PER_M_USD = 0.40
      COST_OUTPUT_PER_M_USD = 1.60
```

3c. In `call`, replace
```ruby
        response = call_openai(prompt)
        parsed   = parse_response(response)
```
with
```ruby
        photos   = Products::Enrichment::PhotoSourceService.new(@product).call
        response = call_openai(prompt, photos.jpegs)
        parsed   = parse_response(response)
        parsed["warnings"] = Array(parsed["warnings"]) + photos.warnings
```

3d. Replace the two rescue clauses at the end of `call` (`rescue RateLimitError => e … raise # re-raise…` and `rescue StandardError => e … raise GenerationError, …`) with:
```ruby
      rescue GenerationError => e
        mark_failed(e)
        raise
      rescue StandardError => e
        mark_failed(e)
        raise GenerationError, "Failed to generate draft for product #{@product.id}: #{e.message}"
```
and add as the first private method:
```ruby
      def mark_failed(error)
        @draft.update!(status: :failed, error_message: "#{error.class}: #{error.message}", generated_at: Time.current)
      end

```

3e. Replace the whole `call_openai` method with:
```ruby
      def call_openai(prompt, jpegs)
        OpenAI::Client.new(request_timeout: REQUEST_TIMEOUT).chat(
          parameters: {
            model:           @model,
            messages:        [
              { role: "system", content: prompt[:system] },
              { role: "user",   content: user_content(prompt[:user], jpegs) }
            ],
            temperature:     0.4,
            response_format: { type: "json_schema",
                               json_schema: { name: "product_enrichment", strict: true,
                                              schema: Products::Enrichment::ResponseSchema.for(@product.attribute_template) } },
            max_tokens:      2000
          }
        )
      rescue Faraday::TooManyRequestsError => e
        raise RateLimitError, "OpenAI está saturado (429): #{e.message}"
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::ServerError => e
        raise TransientError, "OpenAI no respondió: #{e.message}"
      end

      # Sin fotos el mensaje es sólo texto; con fotos, cada una va etiquetada.
      def user_content(text, jpegs)
        return text if jpegs.empty?

        [{ type: "text", text: text }] + jpegs.each_with_index.flat_map do |jpeg, index|
          [{ type: "text", text: "Foto #{index + 1} del producto" },
           { type: "image_url", image_url: { url: "data:image/jpeg;base64,#{Base64.strict_encode64(jpeg)}", detail: "high" } }]
        end
      end
```

3f. In `parse_response`: every `raise GenerationError, …` → `raise InvalidResponseError, …` (three places: empty response, missing `description_es`, non-natural description), and in its `rescue JSON::ParserError => e` → `raise InvalidResponseError, …`.

3g. Replace `estimate_cost` with:
```ruby
      def estimate_cost(usage)
        usd = (usage["prompt_tokens"].to_i / 1_000_000.0 * COST_INPUT_PER_M_USD) +
              (usage["completion_tokens"].to_i / 1_000_000.0 * COST_OUTPUT_PER_M_USD)
        (usd * 100).ceil
      end
```

3h. Update the class comment's step 3 line to `# 3. Call OpenAI (gpt-4.1-mini) with the prompt and up to 3 product photos, strict JSON schema`.

- [ ] **Step 4: Job** — replace the body of `app/jobs/products/enrichment/generate_draft_job.rb`'s class (keep `queue_as :enrichment`, `discard_on ActiveRecord::RecordNotFound`, `perform`) so the handlers read:
```ruby
      # ActiveJob revisa los manejadores de abajo hacia arriba: las subclases
      # (abajo) ganan sobre GenerationError, que se descarta sin reintentar.
      discard_on Products::Enrichment::GenerateDraftService::GenerationError
      retry_on Products::Enrichment::GenerateDraftService::InvalidResponseError, wait: 5.seconds, attempts: 2
      retry_on Products::Enrichment::GenerateDraftService::TransientError, wait: :polynomially_longer, attempts: 3
      retry_on Products::Enrichment::GenerateDraftService::RateLimitError, wait: :polynomially_longer, attempts: 5

      discard_on ActiveRecord::RecordNotFound

      # Encola un borrador nuevo salvo que el producto ya tenga uno pendiente.
      def self.enqueue_for(product)
        return if product.description_drafts.where(status: %i[queued generating draft_generated]).exists?

        perform_later(product.description_drafts.create!(status: :queued).id)
      end
```
(remove the old `retry_on … RateLimitError … attempts: 5` and `retry_on … GenerationError … attempts: 3` lines).

- [ ] **Step 5: Run + commit**
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/products/enrichment spec/jobs/products spec/requests/admin` — Expected: 0 failures.
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/services/products/enrichment app/jobs/products`
```bash
git add app/services/products/enrichment app/jobs/products spec/services/products/enrichment spec/jobs/products
git commit -m "feat: descripción con IA en gpt-4.1-mini con fotos, esquema estricto y reintentos que no bloquean"
```

---

### Task 5: Auto-generate drafts for products created in quick_add

**Files:**
- Modify: `app/services/collectibles/quick_add_service.rb`, `app/jobs/collectibles/copy_photos_to_product_job.rb`, `spec/requests/admin/collectibles_quick_add_enrichment_spec.rb`, `spec/requests/admin/collectibles_quick_add_photos_spec.rb`, `spec/jobs/collectibles/copy_photos_to_product_job_spec.rb`, `spec/system/admin/collectible_ai_lookup_spec.rb`

**Interfaces:**
- Consumes: `GenerateDraftJob.enqueue_for(product)` (Task 4).

- [ ] **Step 1: Failing specs**

`spec/requests/admin/collectibles_quick_add_enrichment_spec.rb` — append before the final `end`:
```ruby
  describe 'borrador automático de descripción' do
    it 'un producto nuevo sin fotos recibe su borrador en cola de inmediato' do
      expect { quick_add }.to have_enqueued_job(Products::Enrichment::GenerateDraftJob)
      expect(Product.order(:id).last.description_drafts.queued.count).to eq(1)
    end

    it 'con vista 3/4 el borrador espera a la copia de fotos' do
      photo = Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/test1.png'), 'image/png')
      expect { quick_add(inventory: { item_condition: 'loose', three_quarter_image: photo }) }
        .to have_enqueued_job(Collectibles::CopyPhotosToProductJob)
        .and(not_have_enqueued_job(Products::Enrichment::GenerateDraftJob))
    end

    it 'un producto existente no recibe borrador' do
      product = create(:product)
      expect do
        post admin_collectibles_quick_add_path, params: { use_existing_product: '1', existing_product_id: product.id,
                                                          inventory: { item_condition: 'loose' } }
      end.not_to have_enqueued_job(Products::Enrichment::GenerateDraftJob)
    end
  end
```
and add at the top of the file, below `include ActiveJob::TestHelper`:
```ruby
  RSpec::Matchers.define_negated_matcher :not_have_enqueued_job, :have_enqueued_job
```

`spec/jobs/collectibles/copy_photos_to_product_job_spec.rb` — append before the final `end`:
```ruby
  it 'al terminar de copiar encola el borrador de descripción, una sola vez' do
    attach_piece('tres_cuartos.png', 'red')
    expect do
      2.times { described_class.perform_now(inventory.id) }
    end.to have_enqueued_job(Products::Enrichment::GenerateDraftJob).exactly(:once)
  end
```

`spec/requests/admin/collectibles_quick_add_photos_spec.rb`: replace `perform_enqueued_jobs do` with `perform_enqueued_jobs(only: Collectibles::CopyPhotosToProductJob) do` (the draft job must not reach OpenAI).

`spec/system/admin/collectible_ai_lookup_spec.rb`, in `'al dar de alta guarda las fotos de los recuadros en orden en la pieza y en el producto nuevo'`: as the first line inside `Dir.mktmpdir do |dir|` add
```ruby
      allow(Products::Enrichment::GenerateDraftJob).to receive(:enqueue_for)
```
and after the `primary_product_image` expectation add
```ruby
      expect(Products::Enrichment::GenerateDraftJob).to have_received(:enqueue_for).with(inventory.product)
```

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/requests/admin/collectibles_quick_add_enrichment_spec.rb spec/jobs/collectibles` — Expected: FAIL (no draft enqueued).

- [ ] **Step 2: Implementation**

`app/services/collectibles/quick_add_service.rb` — replace
```ruby
        # Después del commit, para que el worker encuentre la pieza y sus fotos.
        Collectibles::CopyPhotosToProductJob.perform_later(@inventory.id) if @copy_photos_to_product
```
with
```ruby
        enqueue_follow_up_jobs
```
and add before `def update_product_stats`:
```ruby
    # Después del commit, para que el worker encuentre la pieza y sus fotos. Un
    # producto nuevo recibe su borrador de descripción con IA (para revisión,
    # nunca se publica solo); si hay fotos que copiarle, el borrador lo encola
    # la copia al terminar, para que la IA las vea.
    def enqueue_follow_up_jobs
      return unless @product_created

      if @copy_photos_to_product
        Collectibles::CopyPhotosToProductJob.perform_later(@inventory.id)
      else
        Products::Enrichment::GenerateDraftJob.enqueue_for(@product)
      end
    end

```

`app/jobs/collectibles/copy_photos_to_product_job.rb` — replace
```ruby
      product = inventory.product
      # Idempotente: en un reintento el producto ya tiene fotos y no se duplican.
      return if product.product_images.attached?

      inventory.piece_images.attachments.sort_by(&:id).each { |photo| copy(photo, product) }
    end
```
with
```ruby
      product = inventory.product
      # Idempotente: en un reintento el producto ya tiene fotos y no se duplican.
      unless product.product_images.attached?
        inventory.piece_images.attachments.sort_by(&:id).each { |photo| copy(photo, product) }
      end
      # Con las fotos ya copiadas, la descripción con IA puede verlas.
      Products::Enrichment::GenerateDraftJob.enqueue_for(product)
    end
```

- [ ] **Step 3: Run + commit**
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/requests/admin spec/jobs` — Expected: 0 failures.
Run: `npm run build && RUN_SYSTEM_SPECS=1 RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/system/admin/collectible_ai_lookup_spec.rb` — Expected: 0 failures.
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/services/collectibles app/jobs/collectibles`
```bash
git add app/services/collectibles/quick_add_service.rb app/jobs/collectibles/copy_photos_to_product_job.rb spec/requests/admin/collectibles_quick_add_enrichment_spec.rb spec/requests/admin/collectibles_quick_add_photos_spec.rb spec/jobs/collectibles/copy_photos_to_product_job_spec.rb spec/system/admin/collectible_ai_lookup_spec.rb
git commit -m "feat: quick_add encola el borrador de descripción del producto nuevo"
```

---

### Task 6: Full verification

- [ ] `npm run build && RUN_SYSTEM_SPECS=1 RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec` — Expected: 0 failures.
- [ ] `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app config/routes.rb db/migrate/20261005120000_add_product_to_collectible_ai_lookups.rb` — Expected: no offenses.
- [ ] `graphify update .`
- [ ] After merge + `git push heroku main` (release phase migrates): the admin generates one draft from the enrichment panel for a product with photos, and does one quick_add with identification; then `heroku run --no-tty -- bin/rails runner 'd = ProductDescriptionDraft.order(:id).last; p d.slice(:status, :ai_model, :prompt_version, :estimated_cost_cents, :tokens_input); p d.warnings'`.
