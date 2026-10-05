# Collectible Photo Slots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace quick_add's single photo input with five labeled slots (3/4 elevada, base/casting, lateral, superior, empaque) plus "Más fotos"; send each photo to the AI with its label and the 3/4 view to Google; and, when quick_add creates a new product, save every uploaded photo as a product photo too.

**Architecture:** `Collectibles::AiLookup` gains `photo_roles` (string array aligned with `ordered_photos`) and a cap of 5. `AiLookupService` interleaves a label `input_text` before each image and picks the `three_quarter` photo for Vision. The view renders five `inventory[piece_images][]` inputs as labeled tiles (DOM order = save order) driven by the existing `collectible-ai-lookup` Stimulus controller. `Collectibles::QuickAddService#attach_images` attaches each upload to the piece and, for a newly created product, to `product_images` as separate blobs.

**Tech Stack:** Rails 8.0.1, PostgreSQL (array column), ActiveStorage, `ruby-openai` 8.3, Stimulus bundled by esbuild, RSpec + Capybara/Selenium, ImageMagick `convert` in specs.

**Spec:** `docs/superpowers/specs/2026-10-04-collectible-photo-slots-design.md`

## Global Constraints

- Ruby commands run as `~/.rvm/bin/rvm 3.2.3 do <cmd>`.
- Test DB: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bin/rails db:test:prepare` — never `db:prepare`, never destructive tasks against `inventory_app_development`. `bin/rails db:migrate` (development) is allowed.
- System specs need `RUN_SYSTEM_SPECS=1`; run `npm run build` after any Stimulus change, before system specs.
- Roles, in slot order: `three_quarter`, `base`, `side`, `top`, `package`. AI cap **5** photos. Vision always gets the `three_quarter` photo (first photo when no roles).
- Requests without `photo_roles` (old page) must keep working.
- Product photos are copied **only when quick_add created the product**; each copy is its own blob.
- No spec calls OpenAI or Google. `GOOGLE_VISION_API_KEY` / `OPENAI_API_KEY` never read or printed.
- Admin copy in Mexican Spanish; AI text via `textContent`.
- After code changes run `graphify update .`.
- `spec/fixtures/files/test1.png` and `test2.png` are byte-identical: any spec that must tell photos apart generates its own images with `convert`.

## Review Focus

1. **Admin removes a photo from a slot after choosing it** — expected: thumbnail cleared, that file not uploaded with the form nor sent to the AI, button state recomputed. → Task 4 system spec ("Quitar").
2. **Only the base photo chosen** — expected: AI block visible, button disabled with "Agrega la vista 3/4 elevada…"; manual save still works. → Task 4 system spec.
3. **Admin deletes a piece photo later on the collectible edit page** — expected: the product's copy survives (separate blobs). → Task 3 request spec asserts distinct blob ids.
4. **"Usar producto existente" with photos** — expected: catalog product photos untouched; photos only on the piece. → Task 3 request spec.
5. **Old page open during deploy posts `photos[]` without roles** — expected: lookup works, labels "tipo no indicado", Vision uses the first photo. → Task 1 model spec + Task 2 service spec.

---

### Task 1: Photo roles on the lookup record

**Files:**
- Create: `db/migrate/20261004140000_add_photo_roles_to_collectible_ai_lookups.rb`
- Modify: `db/schema.rb` (generated)
- Modify: `app/models/collectibles/ai_lookup.rb`
- Modify: `app/controllers/admin/collectible_ai_lookups_controller.rb`
- Test: `spec/models/collectibles/ai_lookup_spec.rb`, `spec/requests/admin/collectible_ai_lookups_spec.rb`

**Interfaces:**
- Produces: `AiLookup#photo_roles` (Array<String>, default `[]`), `AiLookup::PHOTO_ROLES` (ordered Hash role → AI label), `AiLookup::MAX_PHOTOS = 5`, `AiLookup#labeled_photos → Array<[ActiveStorage::Attachment, String|nil]>`; `POST admin_collectible_ai_lookups_path` accepts `photo_roles[]`.

- [ ] **Step 1: Failing model specs**

In `spec/models/collectibles/ai_lookup_spec.rb`, change the example `'acepta hasta 3 fotos y rechaza la cuarta con un mensaje claro'`:
- title → `'acepta hasta 5 fotos y rechaza la sexta con un mensaje claro'`
- `3.times { attach(...) }` → `5.times { attach(...) }`
- `include('Máximo 3 fotos')` → `include('Máximo 5 fotos')`

Append before the file's final `end`:
```ruby
  describe 'tipos de foto' do
    def lookup_with(roles, count: roles.size)
      described_class.new(user: admin, photo_roles: roles).tap do |l|
        count.times { attach(l, filename: 'a.png', content_type: 'image/png') }
      end
    end

    it 'acepta tipos válidos que incluyen la vista 3/4' do
      expect(lookup_with(%w[base three_quarter package])).to be_valid
    end

    it 'sigue aceptando búsquedas sin tipos (página vieja)' do
      expect(lookup_with([], count: 2)).to be_valid
    end

    it 'exige la vista 3/4 cuando hay tipos' do
      lookup = lookup_with(%w[base side])
      expect(lookup).not_to be_valid
      expect(lookup.errors.full_messages).to include('Falta la vista 3/4 elevada.')
    end

    it 'rechaza tipos desconocidos, repetidos o que no cuadran con las fotos' do
      [lookup_with(%w[three_quarter selfie]), lookup_with(%w[three_quarter three_quarter]),
       lookup_with(%w[three_quarter], count: 2)].each do |lookup|
        expect(lookup).not_to be_valid
        expect(lookup.errors.full_messages).to include('Los tipos de foto no son válidos.')
      end
    end

    it 'empareja cada foto con su tipo en el orden de subida' do
      lookup = lookup_with(%w[three_quarter base]).tap(&:save!)
      expect(lookup.reload.labeled_photos.map(&:last)).to eq(%w[three_quarter base])
    end

    it 'sin tipos, cada foto queda con tipo nil' do
      lookup = lookup_with([], count: 2).tap(&:save!)
      expect(lookup.reload.labeled_photos.map(&:last)).to eq([nil, nil])
    end
  end
```

- [ ] **Step 2: Failing request specs**

In `spec/requests/admin/collectible_ai_lookups_spec.rb`, change the example `'rechaza más de 3 fotos sin gastar'`:
- title → `'rechaza más de 5 fotos sin gastar'`
- `Array.new(4) { png_upload }` → `Array.new(6) { png_upload }`
- `include('Máximo 3 fotos')` → `include('Máximo 5 fotos')`

Add inside `describe 'POST create'`:
```ruby
    it 'guarda el tipo de cada foto en orden' do
      post admin_collectible_ai_lookups_path,
           params: { photos: [png_upload, png_upload('test2.png')], photo_roles: %w[three_quarter base] }

      expect(response).to have_http_status(:created)
      expect(Collectibles::AiLookup.last.photo_roles).to eq(%w[three_quarter base])
    end

    it 'rechaza tipos sin la vista 3/4' do
      post admin_collectible_ai_lookups_path, params: { photos: [png_upload], photo_roles: %w[base] }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Falta la vista 3/4 elevada.')
    end
```

- [ ] **Step 3: Run to verify failure**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/models/collectibles/ai_lookup_spec.rb spec/requests/admin/collectible_ai_lookups_spec.rb`
Expected: FAIL — `unknown attribute 'photo_roles'` / `Máximo 3 fotos` still in message.

- [ ] **Step 4: Migration**

`db/migrate/20261004140000_add_photo_roles_to_collectible_ai_lookups.rb`:
```ruby
# frozen_string_literal: true

class AddPhotoRolesToCollectibleAiLookups < ActiveRecord::Migration[8.0]
  def change
    add_column :collectible_ai_lookups, :photo_roles, :string, array: true, default: [], null: false
  end
end
```
Run: `~/.rvm/bin/rvm 3.2.3 do bin/rails db:migrate && RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bin/rails db:test:prepare`
Expected: migration runs; `db/schema.rb` gains `t.string "photo_roles", default: [], null: false, array: true` and version `2026_10_04_140000`.

- [ ] **Step 5: Model**

In `app/models/collectibles/ai_lookup.rb`:
- `MAX_PHOTOS = 3` → `MAX_PHOTOS = 5`
- below `HINTS_MAX = 300` add:
```ruby
    # Un recuadro por tipo de foto en quick_add, en este orden. El texto es lo
    # que lee la IA antes de cada foto.
    PHOTO_ROLES = {
      'three_quarter' => 'vista 3/4 elevada de la pieza',
      'base' => 'base de la pieza, donde está el texto del casting (marca, modelo, año, país)',
      'side' => 'vista lateral',
      'top' => 'vista superior',
      'package' => 'empaque (caja, blíster o etiqueta)'
    }.freeze
```
- below `validate :hints_fit` add `validate :photo_roles_are_valid, on: :create`
- below `ordered_photos` add:
```ruby

    # Cada foto con su tipo (nil en búsquedas hechas antes de los recuadros).
    def labeled_photos
      ordered_photos.each_with_index.map { |photo, index| [photo, photo_roles[index]] }
    end
```
- in the private section, after `hints_fit`, add:
```ruby

    # Sin tipos es una página vieja (antes de los recuadros) y se acepta.
    def photo_roles_are_valid
      roles = Array(photo_roles)
      return if roles.empty?

      if roles.size != photos.size || roles.uniq.size != roles.size || (roles - PHOTO_ROLES.keys).any?
        errors.add(:base, 'Los tipos de foto no son válidos.')
      elsif roles.exclude?('three_quarter')
        errors.add(:base, 'Falta la vista 3/4 elevada.')
      end
    end
```
- Update the class comment's "las fotos que se mandaron (hasta 3)" → "las fotos que se mandaron (hasta 5, cada una con su tipo)".

- [ ] **Step 6: Controller**

In `app/controllers/admin/collectible_ai_lookups_controller.rb` `create`, replace
```ruby
      lookup = Collectibles::AiLookup.new(user: current_user, hints: params[:hints].to_s.strip.presence)
```
with
```ruby
      lookup = Collectibles::AiLookup.new(user: current_user, hints: params[:hints].to_s.strip.presence,
                                          photo_roles: Array(params[:photo_roles]).map(&:to_s).compact_blank)
```

- [ ] **Step 7: Run, lint, commit**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/models/collectibles spec/requests/admin/collectible_ai_lookups_spec.rb spec/migrations spec/jobs/collectibles spec/services/collectibles`
Expected: 0 failures.
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/models/collectibles app/controllers/admin/collectible_ai_lookups_controller.rb db/migrate/20261004140000_add_photo_roles_to_collectible_ai_lookups.rb`
```bash
git add db/migrate/20261004140000_add_photo_roles_to_collectible_ai_lookups.rb db/schema.rb app/models/collectibles/ai_lookup.rb app/controllers/admin/collectible_ai_lookups_controller.rb spec/models/collectibles/ai_lookup_spec.rb spec/requests/admin/collectible_ai_lookups_spec.rb
git commit -m "feat: la búsqueda con IA guarda el tipo de cada foto (hasta 5)"
```

---

### Task 2: AI receives a label before each photo; Google gets the 3/4 view

**Files:**
- Modify: `app/services/collectibles/ai_lookup_service.rb`
- Test: `spec/services/collectibles/ai_lookup_service_spec.rb`

**Interfaces:**
- Consumes: `AiLookup#labeled_photos`, `AiLookup::PHOTO_ROLES`.
- Produces: OpenAI `content` = `[main input_text, ("Foto N: <label>" input_text, input_image)…]`.

- [ ] **Step 1: Failing service specs**

In `spec/services/collectibles/ai_lookup_service_spec.rb`:

(a) In the first example replace
```ruby
    expect(params[:instructions]).to include('1) vista 3/4 elevada').and include('2) la base')
```
with
```ruby
    expect(params[:instructions]).to include('Cada foto viene precedida de su tipo')
```

(b) Inside `describe 'fotos, pistas y búsqueda inversa'`, add:
```ruby
    def generated_png(dir, name, color)
      File.join(dir, name).tap { |path| system('convert', '-size', '40x40', "xc:#{color}", path, exception: true) }
    end

    def decoded_images(sent)
      sent.first[:input].first[:content].select { |c| c[:type] == 'input_image' }
          .map { |c| Base64.strict_decode64(c[:image_url].delete_prefix('data:image/jpeg;base64,')) }
    end

    it 'antes de cada foto le dice a la IA qué tipo de foto es' do
      lookup.photos.attach(io: File.open(Rails.root.join('spec/fixtures/files/test2.png')), filename: 'base.png', content_type: 'image/png')
      lookup.save!
      lookup.update!(photo_roles: %w[three_quarter base])
      sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
      described_class.new(lookup.reload).call

      content = sent.first[:input].first[:content]
      expect(content.pluck(:type)).to eq(%w[input_text input_text input_image input_text input_image])
      expect(content[1][:text]).to eq('Foto 1: vista 3/4 elevada de la pieza')
      expect(content[3][:text]).to start_with('Foto 2: base de la pieza, donde está el texto del casting')
    end

    it 'sin tipos (página vieja) etiqueta la foto como sin tipo' do
      sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
      described_class.new(lookup).call
      expect(sent.first[:input].first[:content][1][:text]).to eq('Foto 1 (tipo no indicado)')
    end

    it 'manda a Google la vista 3/4 aunque no sea la primera foto' do
      Dir.mktmpdir do |dir|
        three_quarter = Collectibles::AiLookup.new(user: admin, photo_roles: %w[base three_quarter]).tap do |l|
          l.photos.attach(io: File.open(generated_png(dir, 'base.png', 'blue')), filename: 'base.png', content_type: 'image/png')
          l.photos.attach(io: File.open(generated_png(dir, 'tres_cuartos.png', 'red')), filename: 'tres_cuartos.png', content_type: 'image/png')
          l.save!
        end
        to_google = nil
        allow(Collectibles::ReverseImageSearch).to receive(:new) do |jpeg|
          to_google = jpeg
          instance_double(Collectibles::ReverseImageSearch, call: nil, called?: false)
        end
        sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
        described_class.new(three_quarter.reload).call

        base_jpeg, three_quarter_jpeg = decoded_images(sent)
        expect(base_jpeg).not_to eq(three_quarter_jpeg)
        expect(to_google).to eq(three_quarter_jpeg)
      end
    end

    it 'sin tipos manda a Google la primera foto' do
      to_google = nil
      allow(Collectibles::ReverseImageSearch).to receive(:new) do |jpeg|
        to_google = jpeg
        instance_double(Collectibles::ReverseImageSearch, call: nil, called?: false)
      end
      sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
      described_class.new(lookup).call
      expect(to_google).to eq(decoded_images(sent).first)
    end
```

- [ ] **Step 2: Run to verify failure**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/collectibles/ai_lookup_service_spec.rb`
Expected: FAIL — instructions lack "Cada foto viene precedida", no label `input_text`, Google gets the first photo.

- [ ] **Step 3: Implementation**

In `app/services/collectibles/ai_lookup_service.rb`:

3a. In `INSTRUCTIONS`, replace step 1's two lines
```
      1. Identifica la pieza usando TODAS las fotos: nombre comercial, marca, serie, código del fabricante, escala y año o edición.
         Las fotos suelen venir en este orden: 1) vista 3/4 elevada de la pieza, 2) la base con el texto del casting (marca, modelo, año, país), 3) la caja, blíster o etiqueta. Lee con cuidado el texto de la base y de la caja.
```
with
```
      1. Identifica la pieza usando TODAS las fotos: nombre comercial, marca, serie, código del fabricante, escala y año o edición.
         Cada foto viene precedida de su tipo (vista 3/4, base, lateral, superior, empaque). En la foto de la base lee con cuidado el texto del casting (marca, modelo, año, país); en la del empaque, el texto de la caja o etiqueta.
```

3b. Update the class comment: "a partir de hasta 3 fotos" → "a partir de hasta 5 fotos, cada una con su tipo,"; "búsqueda inversa sobre la primera foto" → "búsqueda inversa sobre la vista 3/4".

3c. In `call`, replace `reverse_image = reverse_image_search(photos.first)` with `reverse_image = reverse_image_search(vision_jpeg(photos))`.

3d. Replace `user_content`'s return expression
```ruby
      [{ type: 'input_text', text: text.join("\n\n") }] +
        photos.map { |jpeg| { type: 'input_image', image_url: "data:image/jpeg;base64,#{Base64.strict_encode64(jpeg)}", detail: 'high' } }
    end
```
with
```ruby
      [{ type: 'input_text', text: text.join("\n\n") }] +
        photos.each_with_index.flat_map do |(jpeg, role), index|
          [{ type: 'input_text', text: photo_label(index, role) },
           { type: 'input_image', image_url: "data:image/jpeg;base64,#{Base64.strict_encode64(jpeg)}", detail: 'high' }]
        end
    end

    def photo_label(index, role)
      label = AiLookup::PHOTO_ROLES[role]
      label ? "Foto #{index + 1}: #{label}" : "Foto #{index + 1} (tipo no indicado)"
    end

    # Google reconoce mejor la vista 3/4; búsquedas sin tipos usan la primera foto.
    def vision_jpeg(photos)
      (photos.find { |_jpeg, role| role == 'three_quarter' } || photos.first).first
    end
```

3e. Replace `processed_photos`:
```ruby
    def processed_photos
      @lookup.labeled_photos.first(MAX_PHOTOS).map { |photo, role| [processed_jpeg(photo), role] }
    end
```

- [ ] **Step 4: Run, lint, commit**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/collectibles spec/jobs/collectibles spec/models/collectibles`
Expected: 0 failures.
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/services/collectibles`
```bash
git add app/services/collectibles/ai_lookup_service.rb spec/services/collectibles/ai_lookup_service_spec.rb
git commit -m "feat: la IA recibe cada foto con su tipo y Google la vista 3/4"
```

---

### Task 3: New products get the uploaded photos as product photos

**Files:**
- Modify: `app/services/collectibles/quick_add_service.rb` (`find_or_create_product`, `attach_images`)
- Test: `spec/requests/admin/collectibles_quick_add_photos_spec.rb` (new)

**Interfaces:**
- Consumes: `params[:inventory][:piece_images]` (array, may contain blanks) — unchanged.
- Produces: for a product created in this request, `product.product_images` mirrors `inventory.piece_images` in order, separate blobs.

- [ ] **Step 1: Failing request spec**

`spec/requests/admin/collectibles_quick_add_photos_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin quick_add guarda las fotos', type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  around do |example|
    Dir.mktmpdir do |dir|
      @dir = dir
      example.run
    end
  end

  def upload(name, color)
    path = File.join(@dir, name)
    system('convert', '-size', '30x30', "xc:#{color}", path, exception: true)
    Rack::Test::UploadedFile.new(path, 'image/png')
  end

  def quick_add(product_params, images)
    post admin_collectibles_quick_add_path, params: {
      inventory: { item_condition: 'loose', piece_images: images }
    }.merge(product_params)
  end

  def new_product_params
    { use_existing_product: '0', product: { product_name: 'Pieza de prueba IA', category: 'Autos a escala' } }
  end

  it 'un producto nuevo recibe las mismas fotos, en el mismo orden, como fotos propias' do
    # Un recuadro vacío llega como "" y se ignora.
    quick_add(new_product_params, [upload('tres_cuartos.png', 'red'), '', upload('base.png', 'blue'), upload('extra.png', 'green')])

    inventory = Inventory.order(:id).last
    product = inventory.product
    piece = inventory.piece_images.attachments.sort_by(&:id)
    catalog = product.product_images.attachments.sort_by(&:id)

    expect(piece.map { |a| a.filename.to_s }).to eq(%w[tres_cuartos.png base.png extra.png])
    expect(catalog.map { |a| a.filename.to_s }).to eq(%w[tres_cuartos.png base.png extra.png])
    expect(product.primary_product_image.filename.to_s).to eq('tres_cuartos.png')
    # Copias independientes: borrar la foto de la pieza no borra la del producto.
    expect(catalog.map(&:blob_id) & piece.map(&:blob_id)).to be_empty
    expect(catalog.map { |a| a.blob.checksum }).to eq(piece.map { |a| a.blob.checksum })
  end

  it 'borrar la foto de la pieza deja intacta la del producto' do
    quick_add(new_product_params, [upload('tres_cuartos.png', 'red')])
    inventory = Inventory.order(:id).last

    inventory.piece_images.attachments.first.purge
    expect(inventory.product.reload.product_images.attachments.size).to eq(1)
    expect(inventory.product.product_images.attachments.first.blob.service.exist?(inventory.product.product_images.attachments.first.blob.key)).to be(true)
  end

  it 'con un producto existente no toca sus fotos de catálogo' do
    product = create(:product)
    expect do
      quick_add({ use_existing_product: '1', existing_product_id: product.id }, [upload('tres_cuartos.png', 'red')])
    end.not_to(change { product.reload.product_images.attachments.count })

    expect(Inventory.order(:id).last.piece_images.attachments.size).to eq(1)
  end

  it 'sin fotos no adjunta nada' do
    quick_add(new_product_params, [''])
    inventory = Inventory.order(:id).last
    expect(inventory.piece_images).not_to be_attached
    expect(inventory.product.product_images).not_to be_attached
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/requests/admin/collectibles_quick_add_photos_spec.rb`
Expected: the first two examples FAIL (product has no photos); the last two pass. If the existing-product example fails because `create(:product)` needs more attributes, read `spec/factories/product.rb` and pass what it needs — a ruling, not a skip.

- [ ] **Step 3: Implementation**

In `app/services/collectibles/quick_add_service.rb`:

3a. In `find_or_create_product`, in the `else` branch, replace
```ruby
        @errors.concat(@product.errors.full_messages) unless @product.save
```
with
```ruby
        @product_created = @product.save
        @errors.concat(@product.errors.full_messages) unless @product_created
```

3b. Replace `attach_images` with:
```ruby
    # Las fotos son de la pieza. Si este alta creó el producto, también se
    # vuelven sus fotos de catálogo, en el mismo orden (la vista 3/4 primero,
    # que queda como principal). Cada attach crea su propio blob: borrar una
    # foto de la pieza no le borra la foto al producto. Un producto existente
    # no se toca.
    def attach_images
      images = Array(@params.dig(:inventory, :piece_images)).compact_blank
      return if images.empty?

      images.each do |image|
        @inventory.piece_images.attach(image)
        @product.product_images.attach(image) if @product_created
      end
    end
```

Note: attaching the same `ActionDispatch::Http::UploadedFile` twice works because ActiveStorage rewinds the io when it computes the checksum and uploads; Step 4's checksum assertion proves both copies hold the same bytes. If it does not, debug (systematic-debugging) — do not weaken the assertion.

- [ ] **Step 4: Run, lint, commit**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/requests/admin/collectibles_quick_add_photos_spec.rb spec/requests/admin/collectibles_images_spec.rb`
Expected: 0 failures.
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/services/collectibles/quick_add_service.rb`
```bash
git add app/services/collectibles/quick_add_service.rb spec/requests/admin/collectibles_quick_add_photos_spec.rb
git commit -m "feat: un producto nuevo de quick_add recibe las fotos como fotos del producto"
```

---

### Task 4: Five labeled photo slots on quick_add

**Files:**
- Modify: `app/views/admin/collectibles/quick_add.html.erb` (photos card body)
- Modify: `app/javascript/controllers/collectible_ai_lookup_controller.js`
- Test: `spec/system/admin/collectible_ai_lookup_spec.rb`

**Interfaces:**
- Consumes: `POST` `photos[]` + `photo_roles[]` (Task 1).
- Produces: Stimulus targets `slot button status panel actions hints`; actions `slotChanged`, `clearSlot`; inputs `#piece_photo_<role>` and `#piece_photo_extra`.

- [ ] **Step 1: Update and add system specs**

In `spec/system/admin/collectible_ai_lookup_spec.rb`:

(a) Add below `def answer … end`:
```ruby
  def attach_slot(role, file = 'test1.png')
    attach_file "piece_photo_#{role}", Rails.root.join('spec/fixtures/files', file), make_visible: true
  end
```

(b) Replace every `attach_file 'inventory[piece_images][]', Rails.root.join('spec/fixtures/files/test1.png')` with `attach_slot('three_quarter')`.

(c) In `'si la IA no está segura…'`, replace
```ruby
    attach_file 'inventory[piece_images][]', [Rails.root.join('spec/fixtures/files/test1.png'), Rails.root.join('spec/fixtures/files/test2.png')]
```
with
```ruby
    attach_slot('three_quarter')
    attach_slot('base', 'test2.png')
```
and after `expect(lookup.photos.count).to eq(2)` add `expect(lookup.photo_roles).to eq(%w[three_quarter base])`.

(d) Delete the whole example `'avisa que sólo manda las primeras 3 fotos'`.

(e) Replace the whole example `'empieza con las fotos y sólo ofrece la IA cuando hay una foto'` with:
```ruby
  it 'empieza con cinco recuadros de fotos y sólo ofrece la IA con la vista 3/4' do
    visit admin_collectibles_quick_add_path

    headers = all('.card-header').map(&:text)
    expect(headers.first).to include('1. Fotos de la pieza (opcional)')
    expect(headers.index { |h| h.include?('2. Producto') }).to eq(1)
    %w[three_quarter base side top package].each do |role|
      expect(page).to have_css("[data-collectible-ai-lookup-target='slot'][data-role='#{role}']")
    end
    expect(page).to have_content('Vista 3/4 elevada').and have_content('Base / casting').and have_content('Empaque')
    expect(page).to have_field('piece_photo_extra', type: 'file')
    expect(page).to have_no_button('Identificar con IA')

    attach_slot('base')
    expect(page).to have_button('Identificar con IA', disabled: true)
    expect(page).to have_content('Agrega la vista 3/4 elevada para identificar con IA.')

    attach_slot('three_quarter')
    expect(page).to have_button('Identificar con IA', disabled: false)
    expect(page).to have_no_content('Agrega la vista 3/4 elevada')
  end

  it 'enseña la miniatura, avisa si falta la base y permite quitar la foto' do
    visit admin_collectibles_quick_add_path
    attach_slot('three_quarter')

    slot = find("[data-collectible-ai-lookup-target='slot'][data-role='three_quarter']")
    expect(slot).to have_css('img[data-slot-preview][src^="blob:"]', visible: :visible)
    expect(page).to have_content('Agrega la foto de la base para que la IA lea el casting.')

    within(slot) { click_button 'Quitar' }
    expect(slot).to have_no_css('img[data-slot-preview]', visible: :visible)
    expect(page).to have_no_button('Identificar con IA')
    expect(page.evaluate_script("document.getElementById('piece_photo_three_quarter').files.length")).to eq(0)
  end

  it 'al dar de alta guarda las fotos de los recuadros en orden en la pieza y en el producto nuevo' do
    Dir.mktmpdir do |dir|
      paths = { 'tres_cuartos.png' => 'red', 'base.png' => 'blue', 'extra.png' => 'green' }.to_h do |name, color|
        [name, File.join(dir, name).tap { |p| system('convert', '-size', '30x30', "xc:#{color}", p, exception: true) }]
      end
      visit admin_collectibles_quick_add_path
      fill_in 'product[product_name]', with: 'Pieza con recuadros'
      attach_file 'piece_photo_base', paths['base.png'], make_visible: true
      attach_file 'piece_photo_three_quarter', paths['tres_cuartos.png'], make_visible: true
      attach_file 'piece_photo_extra', paths['extra.png']
      click_button 'Agregar Coleccionable'

      expect(page).to have_content('Coleccionable agregado', wait: 15)
      inventory = Inventory.order(:id).last
      expect(inventory.piece_images.attachments.sort_by(&:id).map { |a| a.filename.to_s })
        .to eq(%w[tres_cuartos.png base.png extra.png])
      expect(inventory.product.primary_product_image.filename.to_s).to eq('tres_cuartos.png')
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `npm run build && RUN_SYSTEM_SPECS=1 RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/system/admin/collectible_ai_lookup_spec.rb`
Expected: FAIL — `Unable to find file field "piece_photo_three_quarter"` in most examples.

- [ ] **Step 3: View**

In `app/views/admin/collectibles/quick_add.html.erb`, inside the "1. Fotos de la pieza (opcional)" card body, replace the whole `<div class="mb-3">` block that contains `<label class="form-label">Subir fotos</label>` (from that `<div class="mb-3">` through its closing `</div>`, i.e. everything before `<div class="d-none" data-collectible-ai-lookup-target="actions">`) with:
```erb
      <%# Un recuadro por tipo de foto. Todos los campos se llaman inventory[piece_images][]
          para que el alta no cambie: el orden en la página es el orden en que se guardan
          (la vista 3/4 primero, que es la que se busca en Google). %>
      <% photo_slots = [
           ['three_quarter', 'Vista 3/4 elevada ★', 'Obligatoria para la IA; se busca en Google'],
           ['base', 'Base / casting', 'Recomendada: el texto de la base'],
           ['side', 'Lateral', 'Opcional'],
           ['top', 'Superior', 'Opcional'],
           ['package', 'Empaque', 'Opcional: caja, blíster o etiqueta']
         ] %>
      <div class="row g-2 mb-3">
        <% photo_slots.each do |role, title, help| %>
          <div class="col-6 col-md-4 col-lg">
            <div class="border rounded p-2 h-100 text-center <%= role == 'three_quarter' ? 'border-warning' : 'border-secondary-subtle' %>"
                 style="border-width: 2px !important; border-style: dashed !important;"
                 data-collectible-ai-lookup-target="slot" data-role="<%= role %>">
              <label for="piece_photo_<%= role %>" class="d-block mb-1" style="cursor: pointer;">
                <img class="img-fluid rounded mb-1 d-none" alt="Foto: <%= title %>" style="max-height: 110px; object-fit: contain;" data-slot-preview>
                <span class="d-block py-3 text-muted" data-slot-placeholder><i class="fa-solid fa-camera fa-lg" aria-hidden="true"></i></span>
                <span class="d-block fw-semibold small"><%= title %></span>
                <span class="d-block text-muted" style="font-size: .75rem;"><%= help %></span>
              </label>
              <%= file_field_tag 'inventory[piece_images][]', accept: 'image/*', id: "piece_photo_#{role}", class: 'd-none',
                                 data: { action: 'change->collectible-ai-lookup#slotChanged' } %>
              <button type="button" class="btn btn-link btn-sm text-danger p-0 d-none" data-slot-clear
                      data-action="collectible-ai-lookup#clearSlot">Quitar</button>
            </div>
          </div>
        <% end %>
      </div>
      <div class="mb-3">
        <label class="form-label small" for="piece_photo_extra">Más fotos de la pieza (no se mandan a la IA)</label>
        <%= file_field_tag 'inventory[piece_images][]', multiple: true, accept: 'image/*', id: 'piece_photo_extra',
                           class: 'form-control form-control-sm' %>
        <small class="text-muted">
          Las fotos son de esta pieza; si se crea un producto nuevo, también quedan como sus fotos.
          Con la vista 3/4 puedes identificar la pieza con IA y prellenar sus datos, o llenarlos a mano.
        </small>
      </div>
```

- [ ] **Step 4: Stimulus controller**

In `app/javascript/controllers/collectible_ai_lookup_controller.js`:

4a. Replace the header comment's first sentence "Sube hasta 3 fotos y las pistas," with "Sube las fotos de los recuadros (cada una con su tipo) y las pistas,".

4b. Replace `const MAX_PHOTOS = 3` with `const MAX_PHOTOS = 5`.

4c. Replace `static targets = ["fileInput", "button", "status", "panel", "actions", "hints"]` with `static targets = ["slot", "button", "status", "panel", "actions", "hints"]`.

4d. Replace the block from `  // La IA es opcional: el botón sólo aparece cuando hay una foto que mandar.` through the end of `photos() { … }` with:
```javascript
  // Un recuadro por tipo de foto; la IA necesita al menos la vista 3/4.
  slotChanged(event) {
    this.renderSlot(event.target.closest("[data-collectible-ai-lookup-target='slot']"))
    this.refresh()
  }

  clearSlot(event) {
    const slot = event.target.closest("[data-collectible-ai-lookup-target='slot']")
    slot.querySelector("input[type='file']").value = ""
    this.renderSlot(slot)
    this.refresh()
  }

  renderSlot(slot) {
    const file = slot.querySelector("input[type='file']").files?.[0]
    const preview = slot.querySelector("[data-slot-preview]")
    if (preview.src.startsWith("blob:")) URL.revokeObjectURL(preview.src)
    if (file) preview.src = URL.createObjectURL(file)
    else preview.removeAttribute("src")
    preview.classList.toggle("d-none", !file)
    slot.querySelector("[data-slot-placeholder]").classList.toggle("d-none", Boolean(file))
    slot.querySelector("[data-slot-clear]").classList.toggle("d-none", !file)
  }

  // Fotos de los recuadros en su orden, cada una con su tipo.
  photos() {
    return this.slotTargets
      .map((slot) => ({ role: slot.dataset.role, file: slot.querySelector("input[type='file']").files?.[0] }))
      .filter((photo) => photo.file)
      .slice(0, MAX_PHOTOS)
  }

  hasRole(role) { return this.photos().some((photo) => photo.role === role) }

  refresh() {
    const any = this.photos().length > 0
    if (this.hasActionsTarget) this.actionsTarget.classList.toggle("d-none", !any && !this.running)
    if (this.running) return
    const ready = this.hasRole("three_quarter")
    this.buttonTarget.disabled = !ready
    if (!any) this.statusTarget.textContent = ""
    else if (!ready) this.statusTarget.textContent = "Agrega la vista 3/4 elevada para identificar con IA."
    else if (!this.hasRole("base")) this.statusTarget.textContent = "Agrega la foto de la base para que la IA lea el casting."
    else this.statusTarget.textContent = ""
  }
```

4e. In `start()`, replace
```javascript
    const photos = this.photos()
    if (photos.length === 0 || this.running) return
```
with
```javascript
    const photos = this.photos()
    if (!this.hasRole("three_quarter") || this.running) return
```
and replace
```javascript
    photos.forEach((photo) => body.append("photos[]", photo))
```
with
```javascript
    photos.forEach(({ role, file }) => {
      body.append("photos[]", file)
      body.append("photo_roles[]", role)
    })
```

4f. In `setRunning`, replace `this.buttonTarget.disabled = running || this.photos().length === 0` with `this.buttonTarget.disabled = running || !this.hasRole("three_quarter")`.

Run: `grep -n "fileInput\|photoChanged" app/javascript/controllers/collectible_ai_lookup_controller.js app/views/admin/collectibles/quick_add.html.erb`
Expected: no output.

- [ ] **Step 5: Run the system specs**

Run: `node --check app/javascript/controllers/collectible_ai_lookup_controller.js && npm run build && RUN_SYSTEM_SPECS=1 RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/system/admin/collectible_ai_lookup_spec.rb`
Expected: 8 examples, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/views/admin/collectibles/quick_add.html.erb app/javascript/controllers/collectible_ai_lookup_controller.js spec/system/admin/collectible_ai_lookup_spec.rb
git commit -m "feat: cinco recuadros de fotos por tipo en quick_add"
```

---

### Task 5: Full verification

- [ ] **Step 1:** `npm run build && RUN_SYSTEM_SPECS=1 RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec` — Expected: 0 failures.
- [ ] **Step 2:** `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app config/routes.rb db/migrate/20261004140000_add_photo_roles_to_collectible_ai_lookups.rb` — Expected: no offenses.
- [ ] **Step 3:** `graphify update .`
- [ ] **Step 4 (after merge + `git push heroku main`):** `heroku run --no-tty -- bin/rails runner 'p Collectibles::AiLookup.column_names.include?("photo_roles")'` → `true`; the admin does one quick_add with the 3/4 + base slots on a new product; then `heroku run --no-tty -- bin/rails runner 'l = Collectibles::AiLookup.last; p l.photo_roles; p l.vision_used; i = Inventory.order(:id).last; p [i.piece_images.count, i.product.product_images.count]'`.
