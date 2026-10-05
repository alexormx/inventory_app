# Collectible AI Lookup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On `/admin/collectibles/quick_add`, an "Identificar con IA" button sends the chosen photo to OpenAI, which identifies the collectible and searches trusted sites live; the page fills empty form fields and shows launch date, rarity and separate MX / worldwide price ranges with source links.

**Architecture:** A `Collectibles::AiLookup` record holds the photo and the result. `POST` creates it and enqueues `Collectibles::AiLookupJob` on the Solid Queue worker dyno; the job runs `Collectibles::AiLookupService`, which makes one OpenAI Responses API call (image input + `web_search` restricted to an allowlist + strict JSON schema) and drops any listing whose URL is not on the allowlist. A Stimulus controller uploads, polls `GET` for JSON status, fills the form and renders the panel.

**Tech Stack:** Rails 8.0.1, PostgreSQL, Solid Queue, ActiveStorage, `image_processing` (MiniMagick), `ruby-openai` 8.x, Stimulus via importmap, RSpec + Capybara/Selenium.

**Spec:** `docs/superpowers/specs/2026-10-04-collectible-ai-lookup-design.md`

## Global Constraints

- Ruby commands run as `~/.rvm/bin/rvm 3.2.3 do <cmd>` (bare `bin/rails` hits system Ruby 2.7).
- Test DB: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bin/rails db:test:prepare` — never `db:prepare`, never any destructive task against `inventory_app_development`. `bin/rails db:migrate` (development) is allowed.
- System specs only run with `RUN_SYSTEM_SPECS=1`.
- Model: `gpt-4.1` (supports image input and `web_search`; non-reasoning ⇒ search content tokens are free). Prices verified on OpenAI's pricing page 2026-10-04: $2.00 / 1M input, $8.00 / 1M output, $25.00 / 1k web search calls.
- Trusted domains — MX: `mercadolibre.com.mx`, `amazon.com.mx`; WORLDWIDE: `ebay.com`, `amazon.com`, `amazon.co.jp`, `hobbydb.com`, `plazajapan.com`, `hlj.com`.
- Daily limit: 50 lookups app-wide per calendar day. Photo ≤ 15 MB, types `image/jpeg image/png image/webp image/gif`. Stale after 3 minutes. Photo purged 7 days after creation.
- Form filling: only **empty** fields among product name, brand, category, description. SKU and prices are **never** auto-filled.
- No spec calls the real OpenAI API. `OPENAI_API_KEY` is never printed, logged or stored.
- All admin-facing copy in Mexican Spanish. AI-provided strings are rendered with `textContent`, never `innerHTML`.
- After code changes run `graphify update .`.

## Review Focus

1. **iPhone HEIC photo / non-image renamed to .png** — the admin expects a clear message ("usa JPG, PNG, WEBP o GIF" / "no es una imagen válida"), never a paid call. → Task 2 model spec + Task 4 request spec (HEIC); Task 3 service spec (unreadable file, OpenAI not called).
2. **Worldwide listing priced in yen (HLJ, Amazon JP)** — the admin expects USD in the range and the original "¥1,320" visible, not 1320 reported as USD. → schema requires `price_original`; Task 3 sanitize spec keeps it; Task 5 panel shows it.
3. **AI text containing markup** (`<b>`, `<img onerror>`) in a listing title — expected to render as literal text. → Task 5 system spec.
4. **Double click / clicking again while running** — expected one lookup, button disabled until it ends. → Task 5 system spec asserts the button is disabled while running.
5. **Large phone photo (12 MP, with GPS EXIF)** — expected to be downscaled to ≤ 1024 px and stripped of metadata before it leaves the server. → Task 3 service spec decodes the sent image and checks dimensions and absence of EXIF.

---

### Task 1: Upgrade `ruby-openai` to 8.x

**Files:**
- Modify: `Gemfile:30`, `Gemfile.lock`

**Interfaces:**
- Produces: `OpenAI::Client#responses` returning an object with `#create(parameters: Hash) → Hash`.

8.0.0 breaking changes (from the gem CHANGELOG): `require "ruby/openai"` removed (the app never uses it — verified by grep), Ruby 2.6 dropped, responses are JSON-parsed when possible, unknown upload file types warn instead of raising. None affect `client.chat` callers.

- [ ] **Step 1: Bump the gem**

In `Gemfile` replace
```ruby
gem 'ruby-openai', '~> 7.0' # OpenAI API client for product enrichment
```
with
```ruby
gem 'ruby-openai', '~> 8.3' # OpenAI API client: enrichment (chat) y búsqueda con IA (responses)
```
Run: `~/.rvm/bin/rvm 3.2.3 do bundle update ruby-openai --conservative`
Expected: `Gemfile.lock` shows `ruby-openai (8.3.x)`; no other gem changes beyond its own dependencies.

- [ ] **Step 2: Confirm the Responses API exists**

Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec ruby -e 'require "openai"; c = OpenAI::Client.new(access_token: "x"); p c.respond_to?(:responses); p c.responses.class'`
Expected: `true` and `OpenAI::Responses`. If the class name differs, use that name in the spec doubles of Tasks 3 and 5.

- [ ] **Step 3: Run the existing OpenAI callers' specs**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/products/enrichment spec/jobs/products spec/services/purchase_orders`
Expected: 0 failures.

- [ ] **Step 4: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "chore: actualiza ruby-openai a 8.3 para usar la Responses API"
```

---

### Task 2: Lookup model, table and trusted sources

**Files:**
- Create: `db/migrate/20261004120000_create_collectible_ai_lookups.rb`
- Create: `app/models/collectibles/ai_lookup.rb`
- Create: `app/services/collectibles/ai_lookup_sources.rb`
- Modify: `db/schema.rb` (generated)
- Test: `spec/models/collectibles/ai_lookup_spec.rb`, `spec/services/collectibles/ai_lookup_sources_spec.rb`

**Interfaces:**
- Produces:
  - `Collectibles::AiLookup` — `belongs_to :user`, `has_one_attached :photo`, enum `status` (`pending running done failed`), constants `DAILY_LIMIT = 50`, `STALE_AFTER = 3.minutes`, `MAX_PHOTO_BYTES = 15.megabytes`, `PHOTO_CONTENT_TYPES`; `.daily_limit_reached? → Boolean`; `#stale?(now: Time.current) → Boolean`; `#as_status_json → Hash` with keys `:id, :status, :result, :error`.
  - `Collectibles::AiLookupSources::MX`, `::WORLDWIDE`, `::ALL`; `.allowed?(url, market) → Boolean` (`market` is `:mx` or `:world`); `.allowed_anywhere?(url) → Boolean`.

- [ ] **Step 1: Write the failing specs**

`spec/services/collectibles/ai_lookup_sources_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::AiLookupSources do
  describe '.allowed?' do
    it 'acepta subdominios del mercado correcto' do
      expect(described_class.allowed?('https://articulo.mercadolibre.com.mx/MLM-1', :mx)).to be(true)
      expect(described_class.allowed?('https://www.ebay.com/itm/1', :world)).to be(true)
    end

    it 'no confunde amazon.com.mx con amazon.com' do
      expect(described_class.allowed?('https://www.amazon.com.mx/dp/X', :world)).to be(false)
      expect(described_class.allowed?('https://www.amazon.com/dp/X', :mx)).to be(false)
    end

    it 'rechaza dominios fuera de la lista, imitaciones y esquemas raros' do
      expect(described_class.allowed?('https://ebay.com.scam.example/itm/1', :world)).to be(false)
      expect(described_class.allowed?('https://notebay.com/itm/1', :world)).to be(false)
      expect(described_class.allowed?('javascript:alert(1)//ebay.com', :world)).to be(false)
      expect(described_class.allowed?('not a url', :world)).to be(false)
      expect(described_class.allowed?(nil, :mx)).to be(false)
    end
  end

  it '.allowed_anywhere? acepta cualquiera de los dos mercados' do
    expect(described_class.allowed_anywhere?('https://hlj.com/product/x')).to be(true)
    expect(described_class.allowed_anywhere?('https://example.com')).to be(false)
  end
end
```

`spec/models/collectibles/ai_lookup_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::AiLookup do
  let(:admin) { create(:user, :admin) }

  def attach(lookup, filename:, content_type:, io: File.open(Rails.root.join('spec/fixtures/files/test1.png')))
    lookup.photo.attach(io: io, filename: filename, content_type: content_type)
    lookup
  end

  it 'acepta una imagen PNG' do
    lookup = attach(described_class.new(user: admin), filename: 'a.png', content_type: 'image/png')
    expect(lookup).to be_valid
  end

  it 'exige foto' do
    expect(described_class.new(user: admin)).not_to be_valid
  end

  it 'rechaza HEIC con un mensaje que dice qué formatos sirven' do
    lookup = attach(described_class.new(user: admin), filename: 'a.heic', content_type: 'image/heic',
                                                      io: StringIO.new('fake heic'))
    expect(lookup).not_to be_valid
    expect(lookup.errors.full_messages.join).to include('JPG, PNG, WEBP o GIF')
  end

  it 'rechaza fotos de más del tope' do
    stub_const('Collectibles::AiLookup::MAX_PHOTO_BYTES', 10)
    lookup = attach(described_class.new(user: admin), filename: 'a.png', content_type: 'image/png')
    expect(lookup).not_to be_valid
    expect(lookup.errors.full_messages.join).to include('15 MB')
  end

  describe '.daily_limit_reached?' do
    it 'cuenta las búsquedas de hoy de todos los usuarios' do
      stub_const('Collectibles::AiLookup::DAILY_LIMIT', 2)
      2.times { attach(described_class.new(user: create(:user, :admin)), filename: 'a.png', content_type: 'image/png').save! }
      expect(described_class.daily_limit_reached?).to be(true)
    end

    it 'no cuenta las de ayer' do
      stub_const('Collectibles::AiLookup::DAILY_LIMIT', 1)
      travel_to(1.day.ago) { attach(described_class.new(user: admin), filename: 'a.png', content_type: 'image/png').save! }
      expect(described_class.daily_limit_reached?).to be(false)
    end
  end

  describe '#as_status_json' do
    let(:lookup) { attach(described_class.new(user: admin), filename: 'a.png', content_type: 'image/png').tap(&:save!) }

    it 'reporta como fallida una búsqueda atorada más de 3 minutos' do
      lookup.update!(status: :running)
      travel 4.minutes do
        json = lookup.as_status_json
        expect(json[:status]).to eq('failed')
        expect(json[:error]).to include('tardó demasiado')
      end
    end

    it 'sólo expone el resultado cuando terminó' do
      lookup.update!(status: :running, result: { 'x' => 1 })
      expect(lookup.as_status_json[:result]).to be_nil
      lookup.update!(status: :done)
      expect(lookup.as_status_json[:result]).to eq('x' => 1)
    end
  end
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/models/collectibles/ai_lookup_spec.rb spec/services/collectibles/ai_lookup_sources_spec.rb`
Expected: FAIL with `uninitialized constant Collectibles::AiLookup` / `Collectibles::AiLookupSources`.

- [ ] **Step 3: Migration**

`db/migrate/20261004120000_create_collectible_ai_lookups.rb`:
```ruby
# frozen_string_literal: true

class CreateCollectibleAiLookups < ActiveRecord::Migration[8.0]
  def change
    create_table :collectible_ai_lookups do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :status, null: false, default: 0
      t.jsonb :result
      t.text :error_message
      t.string :ai_model
      t.integer :tokens_input
      t.integer :tokens_output
      t.integer :web_search_calls
      t.integer :estimated_cost_cents
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :collectible_ai_lookups, :created_at
  end
end
```
Run: `~/.rvm/bin/rvm 3.2.3 do bin/rails db:migrate` then `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bin/rails db:test:prepare`
Expected: `db/schema.rb` gains `create_table "collectible_ai_lookups"` with `t.jsonb "result"`.

- [ ] **Step 4: Sources**

`app/services/collectibles/ai_lookup_sources.rb`:
```ruby
# frozen_string_literal: true

module Collectibles
  # Sitios en los que confiamos para precios y fechas. La IA sólo busca aquí y,
  # además, el servidor tira cualquier enlace que no sea de esta lista: un
  # enlace inventado nunca llega a la pantalla. México y el resto del mundo van
  # separados porque el precio local y el internacional se leen distinto.
  module AiLookupSources
    MX = %w[mercadolibre.com.mx amazon.com.mx].freeze
    WORLDWIDE = %w[ebay.com amazon.com amazon.co.jp hobbydb.com plazajapan.com hlj.com].freeze
    ALL = (MX + WORLDWIDE).freeze

    module_function

    def allowed?(url, market)
      domains = market == :mx ? MX : WORLDWIDE
      host = https_host(url)
      host.present? && domains.any? { |domain| host == domain || host.end_with?(".#{domain}") }
    end

    def allowed_anywhere?(url)
      allowed?(url, :mx) || allowed?(url, :world)
    end

    def https_host(url)
      uri = URI.parse(url.to_s)
      return nil unless uri.is_a?(URI::HTTP)

      uri.host.to_s.downcase
    rescue URI::InvalidURIError
      nil
    end
  end
end
```

- [ ] **Step 5: Model**

`app/models/collectibles/ai_lookup.rb`:
```ruby
# frozen_string_literal: true

module Collectibles
  # Una identificación con IA pedida desde quick_add: la foto que se mandó, en
  # qué va y lo que contestó. Se guarda aunque falle para poder ver costo y
  # motivo; la foto se purga a los 7 días (AiLookupPhotoPurgeJob).
  class AiLookup < ApplicationRecord
    self.table_name = 'collectible_ai_lookups'

    DAILY_LIMIT = 50
    STALE_AFTER = 3.minutes
    MAX_PHOTO_BYTES = 15.megabytes
    PHOTO_CONTENT_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

    belongs_to :user
    has_one_attached :photo

    enum :status, { pending: 0, running: 1, done: 2, failed: 3 }

    validate :photo_is_supported_image, on: :create

    def self.daily_limit_reached?
      where(created_at: Time.current.all_day).count >= DAILY_LIMIT
    end

    # Si el worker se cae o OpenAI se cuelga, la página no debe girar para siempre.
    def stale?(now: Time.current)
      (pending? || running?) && created_at < now - STALE_AFTER
    end

    def as_status_json
      if stale?
        { id: id, status: 'failed', result: nil, error: 'La búsqueda tardó demasiado. Intenta de nuevo.' }
      else
        { id: id, status: status, result: done? ? result : nil, error: failed? ? error_message : nil }
      end
    end

    private

    def photo_is_supported_image
      unless photo.attached?
        errors.add(:photo, 'es obligatoria')
        return
      end

      unless PHOTO_CONTENT_TYPES.include?(photo.blob.content_type)
        errors.add(:photo, 'tiene un formato no soportado: usa JPG, PNG, WEBP o GIF')
      end
      errors.add(:photo, 'pesa más de 15 MB') if photo.blob.byte_size > MAX_PHOTO_BYTES
    end
  end
end
```

- [ ] **Step 6: Run the specs**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/models/collectibles/ai_lookup_spec.rb spec/services/collectibles/ai_lookup_sources_spec.rb`
Expected: all pass. (A non-image file renamed to `.png` passes this validation — ActiveStorage falls back to the filename when the bytes are unrecognisable. Task 3 rejects it when MiniMagick cannot read it, before any OpenAI call.)

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20261004120000_create_collectible_ai_lookups.rb db/schema.rb app/models/collectibles/ai_lookup.rb app/services/collectibles/ai_lookup_sources.rb spec/models/collectibles/ai_lookup_spec.rb spec/services/collectibles/ai_lookup_sources_spec.rb
git commit -m "feat: registro de búsquedas con IA y lista de sitios confiables"
```

---

### Task 3: `AiLookupService` — one Responses call, validated answer

**Files:**
- Create: `app/services/collectibles/ai_lookup_service.rb`
- Create: `app/services/collectibles/ai_lookup_schema.rb`
- Create: `spec/support/ai_lookup_openai_helpers.rb`
- Test: `spec/services/collectibles/ai_lookup_service_spec.rb`

**Interfaces:**
- Consumes: `Collectibles::AiLookup#photo`, `Collectibles::AiLookupSources.allowed?/allowed_anywhere?/ALL`.
- Produces:
  - `Collectibles::AiLookupService.new(lookup, client: nil).call → Collectibles::AiLookupService::Result` (Struct: `data` Hash, `tokens_input`, `tokens_output`, `web_search_calls`, `cost_cents` Integers).
  - Errors: `Collectibles::AiLookupService::Error < StandardError`, `RateLimitError < Error`, `NotConfiguredError < Error`.
  - `Collectibles::AiLookupService::MODEL = 'gpt-4.1'`.
  - Spec helpers `ai_lookup_answer(overrides = {}) → Hash` and `ai_lookup_openai_response(answer, searches: 3, input_tokens: 4000, output_tokens: 1200) → Hash`.

- [ ] **Step 1: Spec helpers (shared with Tasks 4–5)**

`spec/support/ai_lookup_openai_helpers.rb`:
```ruby
# frozen_string_literal: true

# Respuestas falsas de la Responses API de OpenAI para la búsqueda con IA.
# Ningún spec llama a OpenAI de verdad.
module AiLookupOpenaiHelpers
  def ai_lookup_answer(overrides = {})
    {
      'identification' => {
        'product_name' => 'Tomica No. 23 Nissan Skyline GT-R R34', 'brand' => 'Tomica',
        'series' => 'Tomica regular', 'model_code' => 'No. 23', 'scale' => '1/62',
        'year_or_edition' => '2019', 'confidence' => 0.86, 'notes' => 'Caja roja y blanca.'
      },
      'launch_date' => { 'value' => '2019-06', 'source_url' => 'https://www.hobbydb.com/marketplaces/1' },
      'rarity' => { 'level' => 'poco_comun', 'reasons' => ['Descontinuado en 2022'] },
      'prices_mx' => {
        'min' => 1, 'max' => 1, 'currency' => 'MXN',
        'listings' => [
          { 'title' => 'Tomica Skyline R34', 'price' => 349.0, 'price_original' => '$349 MXN',
            'url' => 'https://articulo.mercadolibre.com.mx/MLM-1', 'sold' => false },
          { 'title' => 'Tomica 23 GT-R', 'price' => 420.0, 'price_original' => '$420 MXN',
            'url' => 'https://www.amazon.com.mx/dp/B01', 'sold' => true }
        ]
      },
      'prices_world' => {
        'min' => 1, 'max' => 1, 'currency' => 'USD',
        'listings' => [
          { 'title' => 'Tomica #23 R34', 'price' => 8.9, 'price_original' => '¥1,320',
            'url' => 'https://www.hlj.com/tomica-23', 'sold' => false }
        ]
      },
      'suggested' => { 'category' => 'Autos a escala',
                       'description_es' => 'Réplica a escala 1/62 del Nissan Skyline GT-R R34 de la línea regular de Tomica.' },
      'warnings' => []
    }.merge(overrides)
  end

  def ai_lookup_openai_response(answer, searches: 3, input_tokens: 4000, output_tokens: 1200)
    {
      'output' => Array.new(searches) { { 'type' => 'web_search_call', 'status' => 'completed' } } + [
        { 'type' => 'message', 'content' => [{ 'type' => 'output_text', 'text' => answer.to_json, 'annotations' => [] }] }
      ],
      'usage' => { 'input_tokens' => input_tokens, 'output_tokens' => output_tokens }
    }
  end

  # Cliente falso: devuelve `response` (o ejecuta el bloque) y guarda los parámetros enviados.
  def stub_ai_lookup_openai(response = nil, &block)
    responses_api = double('OpenAI::Responses')
    sent = []
    allow(responses_api).to receive(:create) do |parameters:|
      sent << parameters
      block ? block.call(parameters) : response
    end
    allow(OpenAI::Client).to receive(:new).and_return(double('OpenAI::Client', responses: responses_api))
    sent
  end
end

RSpec.configure { |config| config.include AiLookupOpenaiHelpers }
```

- [ ] **Step 2: Write the failing service spec**

`spec/services/collectibles/ai_lookup_service_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::AiLookupService do
  let(:admin) { create(:user, :admin) }
  let(:lookup) do
    Collectibles::AiLookup.new(user: admin).tap do |l|
      l.photo.attach(io: File.open(Rails.root.join('spec/fixtures/files/test1.png')), filename: 'a.png', content_type: 'image/png')
      l.save!
    end
  end

  before { allow(OpenAI.configuration).to receive(:access_token).and_return('test-key') }

  it 'manda una sola llamada con imagen, búsqueda restringida y esquema estricto' do
    sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
    described_class.new(lookup).call

    expect(sent.size).to eq(1)
    params = sent.first
    expect(params[:model]).to eq('gpt-4.1')
    expect(params[:tools]).to eq([{ type: 'web_search', filters: { allowed_domains: Collectibles::AiLookupSources::ALL } }])
    expect(params.dig(:text, :format, :type)).to eq('json_schema')
    expect(params.dig(:text, :format, :strict)).to be(true)
    image = params[:input].first[:content].find { |c| c[:type] == 'input_image' }
    expect(image[:image_url]).to start_with('data:image/jpeg;base64,')
  end

  it 'devuelve el resultado, tokens, búsquedas y costo' do
    stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer, searches: 4, input_tokens: 5000, output_tokens: 1000))
    result = described_class.new(lookup).call

    expect(result.data.dig('identification', 'brand')).to eq('Tomica')
    expect(result.tokens_input).to eq(5000)
    expect(result.tokens_output).to eq(1000)
    expect(result.web_search_calls).to eq(4)
    # 5000*2/1M + 1000*8/1M + 4*25/1000 = 0.01 + 0.008 + 0.1 = 0.118 USD → 12 centavos
    expect(result.cost_cents).to eq(12)
  end

  it 'recalcula el rango con los enlaces que sobreviven y conserva el precio original' do
    stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
    data = described_class.new(lookup).call.data

    expect(data['prices_mx'].slice('min', 'max')).to eq('min' => 349.0, 'max' => 420.0)
    expect(data['prices_mx']['currency']).to eq('MXN')
    expect(data.dig('prices_world', 'listings', 0, 'price_original')).to eq('¥1,320')
    expect(data['prices_world']['currency']).to eq('USD')
  end

  it 'tira enlaces fuera de la lista o del mercado equivocado' do
    answer = ai_lookup_answer
    answer['prices_mx']['listings'] << { 'title' => 'Fake', 'price' => 10.0, 'price_original' => '$10',
                                         'url' => 'https://scam.example/x', 'sold' => true }
    answer['prices_world']['listings'] << { 'title' => 'MX en mundial', 'price' => 5.0, 'price_original' => '$5',
                                            'url' => 'https://www.amazon.com.mx/dp/Z', 'sold' => false }
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    data = described_class.new(lookup).call.data

    expect(data['prices_mx']['listings'].map { |l| l['url'] }).not_to include('https://scam.example/x')
    expect(data['prices_mx']['min']).to eq(349.0)
    expect(data['prices_world']['listings'].size).to eq(1)
  end

  it 'deja en null un mercado sin enlaces confiables' do
    answer = ai_lookup_answer
    answer['prices_mx']['listings'] = [{ 'title' => 'x', 'price' => 1.0, 'price_original' => '$1',
                                         'url' => 'https://example.com/x', 'sold' => false }]
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    expect(described_class.new(lookup).call.data['prices_mx']).to be_nil
  end

  it 'limita a 5 enlaces por mercado' do
    answer = ai_lookup_answer
    answer['prices_world']['listings'] = Array.new(8) do |i|
      { 'title' => "L#{i}", 'price' => 10.0 + i, 'price_original' => '$', 'url' => "https://www.ebay.com/itm/#{i}", 'sold' => true }
    end
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    expect(described_class.new(lookup).call.data['prices_world']['listings'].size).to eq(5)
  end

  it 'quita la fuente de la fecha si no es confiable y lo avisa' do
    answer = ai_lookup_answer('launch_date' => { 'value' => '2019', 'source_url' => 'https://blog.example/x' })
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    data = described_class.new(lookup).call.data

    expect(data['launch_date']).to eq('value' => '2019', 'source_url' => nil)
    expect(data['warnings'].join).to include('fecha de lanzamiento')
  end

  it 'falla con un error legible ante JSON roto' do
    response = ai_lookup_openai_response(ai_lookup_answer)
    response['output'].last['content'].first['text'] = '{"identification": '
    stub_ai_lookup_openai(response)
    expect { described_class.new(lookup).call }.to raise_error(described_class::Error, /Respuesta inválida/)
  end

  it 'falla si OpenAI rechaza la solicitud' do
    stub_ai_lookup_openai('output' => [{ 'type' => 'message', 'content' => [{ 'type' => 'refusal', 'refusal' => 'no' }] }],
                          'usage' => {})
    expect { described_class.new(lookup).call }.to raise_error(described_class::Error, /rechazó/)
  end

  it 'convierte el 429 en RateLimitError' do
    stub_ai_lookup_openai { raise Faraday::TooManyRequestsError, 'the server responded with status 429' }
    expect { described_class.new(lookup).call }.to raise_error(described_class::RateLimitError)
  end

  it 'falla claro si no hay llave configurada' do
    allow(OpenAI.configuration).to receive(:access_token).and_return(nil)
    expect { described_class.new(lookup).call }.to raise_error(described_class::NotConfiguredError, /no está configurado/)
  end

  it 'no llama a OpenAI si el archivo no es una imagen legible' do
    lookup.photo.attach(io: StringIO.new('hola, no soy imagen'), filename: 'falsa.png', content_type: 'image/png')
    sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))

    expect { described_class.new(lookup).call }.to raise_error(described_class::Error, /no es una imagen válida/)
    expect(sent).to be_empty
  end

  it 'reduce la foto a 1024 px y le quita los metadatos antes de mandarla' do
    big = Tempfile.new(['big', '.jpg'])
    system('convert', '-size', '3000x2000', 'xc:red', '-set', 'comment', 'GPS 19.43,-99.13', big.path, exception: true)
    lookup.photo.attach(io: File.open(big.path), filename: 'big.jpg', content_type: 'image/jpeg')

    sent = stub_ai_lookup_openai(ai_lookup_openai_response(ai_lookup_answer))
    described_class.new(lookup).call

    data_url = sent.first[:input].first[:content].find { |c| c[:type] == 'input_image' }[:image_url]
    jpeg = Base64.strict_decode64(data_url.delete_prefix('data:image/jpeg;base64,'))
    image = MiniMagick::Image.read(jpeg)
    expect([image.width, image.height].max).to be <= 1024
    expect(image['%c'].to_s).not_to include('GPS')
  ensure
    big&.close!
  end
end
```

- [ ] **Step 3: Run it to verify it fails**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/collectibles/ai_lookup_service_spec.rb`
Expected: FAIL with `uninitialized constant Collectibles::AiLookupService`.

- [ ] **Step 4: Schema**

`app/services/collectibles/ai_lookup_schema.rb`:
```ruby
# frozen_string_literal: true

module Collectibles
  # Esquema estricto (Structured Outputs) de la respuesta. En modo estricto todo
  # campo va en `required` y lo opcional se expresa como null.
  module AiLookupSchema
    LISTING = {
      type: 'object', additionalProperties: false,
      required: %w[title price price_original url sold],
      properties: {
        title: { type: 'string' },
        price: { type: 'number' },
        price_original: { type: 'string' },
        url: { type: 'string' },
        sold: { type: 'boolean' }
      }
    }.freeze

    def self.market(currency)
      {
        anyOf: [
          {
            type: 'object', additionalProperties: false,
            required: %w[min max currency listings],
            properties: {
              min: { type: 'number' }, max: { type: 'number' },
              currency: { type: 'string', enum: [currency] },
              listings: { type: 'array', items: LISTING }
            }
          },
          { type: 'null' }
        ]
      }
    end

    NULLABLE_STRING = { type: %w[string null] }.freeze

    SCHEMA = {
      type: 'object', additionalProperties: false,
      required: %w[identification launch_date rarity prices_mx prices_world suggested warnings],
      properties: {
        identification: {
          type: 'object', additionalProperties: false,
          required: %w[product_name brand series model_code scale year_or_edition confidence notes],
          properties: {
            product_name: { type: 'string' }, brand: NULLABLE_STRING, series: NULLABLE_STRING,
            model_code: NULLABLE_STRING, scale: NULLABLE_STRING, year_or_edition: NULLABLE_STRING,
            confidence: { type: 'number' }, notes: NULLABLE_STRING
          }
        },
        launch_date: {
          type: 'object', additionalProperties: false, required: %w[value source_url],
          properties: { value: NULLABLE_STRING, source_url: NULLABLE_STRING }
        },
        rarity: {
          type: 'object', additionalProperties: false, required: %w[level reasons],
          properties: {
            level: { type: %w[string null], enum: ['comun', 'poco_comun', 'rara', 'muy_rara', nil] },
            reasons: { type: 'array', items: { type: 'string' } }
          }
        },
        prices_mx: market('MXN'),
        prices_world: market('USD'),
        suggested: {
          type: 'object', additionalProperties: false, required: %w[category description_es],
          properties: { category: NULLABLE_STRING, description_es: NULLABLE_STRING }
        },
        warnings: { type: 'array', items: { type: 'string' } }
      }
    }.freeze
  end
end
```

- [ ] **Step 5: Service**

`app/services/collectibles/ai_lookup_service.rb`:
```ruby
# frozen_string_literal: true

module Collectibles
  # Identifica un coleccionable a partir de su foto y busca en sitios confiables
  # fecha de lanzamiento, rareza y precios (México y mundial por separado).
  #
  # Una sola llamada a la Responses API: imagen + web_search restringido a
  # AiLookupSources + esquema estricto. Lo que regresa la IA se valida aquí: un
  # enlace fuera de la lista se tira y el rango se recalcula con lo que queda.
  # No sabe nada de HTTP ni de la pantalla; AiLookupJob guarda el resultado.
  class AiLookupService
    class Error < StandardError; end
    class RateLimitError < Error; end
    class NotConfiguredError < Error; end

    MODEL = 'gpt-4.1'
    REQUEST_TIMEOUT = 90
    IMAGE_MAX_EDGE = 1024
    MAX_LISTINGS = 5
    # USD, página de precios de OpenAI verificada el 2026-10-04 (gpt-4.1; en
    # modelos no razonadores los tokens del contenido buscado no se cobran).
    COST_INPUT_PER_M_USD = 2.00
    COST_OUTPUT_PER_M_USD = 8.00
    COST_PER_1K_SEARCHES_USD = 25.00

    INSTRUCTIONS = <<~PROMPT
      Eres experto en coleccionables (autos a escala, Tomica, Hot Wheels, figuras) para la tienda mexicana "Pasatiempos a Escala".
      1. Identifica la pieza de la foto: nombre comercial, marca, serie, código del fabricante, escala y año o edición.
      2. Busca en la web (sólo en los sitios permitidos) su fecha de lanzamiento, qué tan rara es y precios reales.
      3. prices_mx: sólo anuncios de mercadolibre.com.mx y amazon.com.mx, precio en MXN.
         prices_world: sólo ebay.com, amazon.com, amazon.co.jp, hobbydb.com, plazajapan.com y hlj.com; convierte cada precio a USD en `price` y pon el precio tal como aparece (con su moneda) en `price_original`.
      4. Cada anuncio debe ser de la misma pieza y llevar su URL real. Marca `sold` = true sólo si es una venta concluida.
      5. Si no encuentras datos confiables para un mercado, ese mercado es null. Nunca inventes precios, fechas ni URLs.
      6. launch_date.value en formato YYYY-MM-DD, YYYY-MM o YYYY según lo que sepas con certeza; null si no lo sabes.
      7. rarity.level: comun, poco_comun, rara o muy_rara, con razones concretas (tiraje, edición limitada, descontinuado, variante).
      8. suggested.description_es: 1 o 2 párrafos breves y factuales en español de México; sin precios, sin códigos de tiendas, sin SKUs, sin URLs.
      9. confidence de 0.0 a 1.0 sobre la identificación. Anota dudas en warnings.
      10. Haz como máximo 6 búsquedas.
    PROMPT

    USER_TEXT = 'Identifica este coleccionable y dame fecha de lanzamiento, rareza y precios en México y en el mundo.'

    Result = Struct.new(:data, :tokens_input, :tokens_output, :web_search_calls, :cost_cents, keyword_init: true)

    def initialize(lookup, client: nil)
      @lookup = lookup
      @client = client
    end

    def call
      raise NotConfiguredError, 'OpenAI no está configurado' if OpenAI.configuration.access_token.blank?

      response = request(image_data_url)
      usage = response['usage'] || {}
      searches = Array(response['output']).count { |item| item['type'] == 'web_search_call' }

      Result.new(
        data: sanitize(parse(response)),
        tokens_input: usage['input_tokens'].to_i,
        tokens_output: usage['output_tokens'].to_i,
        web_search_calls: searches,
        cost_cents: cost_cents(usage['input_tokens'].to_i, usage['output_tokens'].to_i, searches)
      )
    rescue Faraday::TooManyRequestsError => e
      raise RateLimitError, "OpenAI está saturado (429): #{e.message}"
    end

    private

    def client
      @client ||= OpenAI::Client.new(request_timeout: REQUEST_TIMEOUT)
    end

    def request(image_url)
      client.responses.create(parameters: {
                                model: MODEL,
                                instructions: INSTRUCTIONS,
                                input: [{
                                  role: 'user',
                                  content: [
                                    { type: 'input_text', text: USER_TEXT },
                                    { type: 'input_image', image_url: image_url, detail: 'high' }
                                  ]
                                }],
                                tools: [{ type: 'web_search', filters: { allowed_domains: AiLookupSources::ALL } }],
                                text: { format: { type: 'json_schema', name: 'collectible_lookup',
                                                  schema: AiLookupSchema::SCHEMA, strict: true } }
                              })
    end

    # La foto de un teléfono pesa varios MB y trae GPS en el EXIF: se reduce y se
    # limpia antes de salir del servidor, y nunca se carga el original como base64.
    def image_data_url
      @lookup.photo.blob.open do |file|
        # `.strip` se pasa tal cual a ImageMagick como -strip (quita EXIF/GPS y comentarios).
        resized = ImageProcessing::MiniMagick.source(file.path)
                                             .resize_to_limit(IMAGE_MAX_EDGE, IMAGE_MAX_EDGE)
                                             .strip
                                             .convert('jpg')
                                             .saver(quality: 85)
                                             .call
        begin
          "data:image/jpeg;base64,#{Base64.strict_encode64(File.binread(resized.path))}"
        ensure
          resized.close!
        end
      end
    rescue MiniMagick::Error, ImageProcessing::Error => e
      raise Error, "La foto no es una imagen válida: #{e.message.lines.first.to_s.strip}"
    end

    def parse(response)
      message = Array(response['output']).find { |item| item['type'] == 'message' }
      content = Array(message&.dig('content'))
      refusal = content.find { |c| c['type'] == 'refusal' }
      raise Error, "OpenAI rechazó la solicitud: #{refusal['refusal']}" if refusal

      text = content.find { |c| c['type'] == 'output_text' }&.dig('text')
      raise Error, 'Respuesta vacía de OpenAI' if text.blank?

      data = JSON.parse(text)
      raise Error, 'Respuesta inválida de OpenAI: falta identification' unless data.is_a?(Hash) && data['identification'].is_a?(Hash)

      data
    rescue JSON::ParserError => e
      Rails.logger.warn("[AiLookup] JSON inválido lookup=#{@lookup.id}: #{text.to_s.truncate(2000)}")
      raise Error, "Respuesta inválida de OpenAI: #{e.message}"
    end

    def sanitize(data)
      data = data.deep_dup
      data['warnings'] = Array(data['warnings'])
      data['prices_mx'] = sanitize_market(data['prices_mx'], :mx, 'MXN')
      data['prices_world'] = sanitize_market(data['prices_world'], :world, 'USD')

      launch = data['launch_date']
      if launch.is_a?(Hash) && launch['source_url'].present? && !AiLookupSources.allowed_anywhere?(launch['source_url'])
        launch['source_url'] = nil
        data['warnings'] << 'La fuente de la fecha de lanzamiento no es un sitio confiable; verifícala.'
      end
      data
    end

    def sanitize_market(market, key, currency)
      return nil unless market.is_a?(Hash)

      listings = Array(market['listings']).select do |listing|
        listing.is_a?(Hash) && AiLookupSources.allowed?(listing['url'], key) &&
          listing['price'].is_a?(Numeric) && listing['price'].positive?
      end.first(MAX_LISTINGS)
      return nil if listings.empty?

      prices = listings.map { |listing| listing['price'] }
      { 'min' => prices.min, 'max' => prices.max, 'currency' => currency, 'listings' => listings }
    end

    def cost_cents(input_tokens, output_tokens, searches)
      usd = (input_tokens / 1_000_000.0 * COST_INPUT_PER_M_USD) +
            (output_tokens / 1_000_000.0 * COST_OUTPUT_PER_M_USD) +
            (searches / 1000.0 * COST_PER_1K_SEARCHES_USD)
      (usd * 100).ceil
    end
  end
end
```

- [ ] **Step 6: Run the spec**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/collectibles/ai_lookup_service_spec.rb`
Expected: all pass. Note `(0.118 * 100).ceil` is 12; if float error yields 11.8000…01 → 12 still, fine.

- [ ] **Step 7: Lint and commit**

Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/services/collectibles/ai_lookup_service.rb app/services/collectibles/ai_lookup_schema.rb` — fix offenses.
```bash
git add app/services/collectibles/ai_lookup_service.rb app/services/collectibles/ai_lookup_schema.rb spec/support/ai_lookup_openai_helpers.rb spec/services/collectibles/ai_lookup_service_spec.rb
git commit -m "feat: identificación con IA por foto con búsqueda en sitios confiables"
```

---

### Task 4: Job, endpoints and photo purge

**Files:**
- Create: `app/jobs/collectibles/ai_lookup_job.rb`
- Create: `app/jobs/collectibles/ai_lookup_photo_purge_job.rb`
- Create: `app/controllers/admin/collectible_ai_lookups_controller.rb`
- Modify: `config/routes.rb:27-29` (admin namespace, beside the quick_add routes)
- Modify: `config/recurring.yml` (production section)
- Test: `spec/jobs/collectibles/ai_lookup_job_spec.rb`, `spec/jobs/collectibles/ai_lookup_photo_purge_job_spec.rb`, `spec/requests/admin/collectible_ai_lookups_spec.rb`

**Interfaces:**
- Consumes: `Collectibles::AiLookup`, `Collectibles::AiLookupService` (+ errors, `MODEL`, `Result`).
- Produces:
  - `POST admin_collectible_ai_lookups_path` (`/admin/collectibles/ai_lookups`), multipart param `photo` → 201 `{ id:, status_url: }`; 422 `{ error: }`; 429 `{ error: }`.
  - `GET admin_collectible_ai_lookup_path(id)` → 200 `AiLookup#as_status_json`; 404 for another user's lookup.
  - `Collectibles::AiLookupJob.perform_later(lookup_id)`.

- [ ] **Step 1: Failing job spec**

`spec/jobs/collectibles/ai_lookup_job_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::AiLookupJob do
  include ActiveJob::TestHelper

  let(:lookup) do
    Collectibles::AiLookup.new(user: create(:user, :admin)).tap do |l|
      l.photo.attach(io: File.open(Rails.root.join('spec/fixtures/files/test1.png')), filename: 'a.png', content_type: 'image/png')
      l.save!
    end
  end

  let(:service) { instance_double(Collectibles::AiLookupService) }

  before { allow(Collectibles::AiLookupService).to receive(:new).and_return(service) }

  it 'guarda resultado, uso y costo' do
    allow(service).to receive(:call).and_return(
      Collectibles::AiLookupService::Result.new(data: { 'identification' => {} }, tokens_input: 10,
                                                tokens_output: 5, web_search_calls: 2, cost_cents: 6)
    )
    described_class.perform_now(lookup.id)

    lookup.reload
    expect(lookup).to be_done
    expect(lookup.result).to eq('identification' => {})
    expect(lookup.slice(:tokens_input, :tokens_output, :web_search_calls, :estimated_cost_cents).values).to eq([10, 5, 2, 6])
    expect(lookup.ai_model).to eq('gpt-4.1')
    expect(lookup.finished_at).to be_present
  end

  it 'marca fallida con el motivo ante un error de la IA y no reintenta' do
    allow(service).to receive(:call).and_raise(Collectibles::AiLookupService::Error, 'Respuesta vacía de OpenAI')
    described_class.perform_now(lookup.id)

    expect(lookup.reload).to be_failed
    expect(lookup.error_message).to include('Respuesta vacía')
    expect(enqueued_jobs).to be_empty
  end

  it 'reintenta el 429 y al agotar los intentos marca fallida' do
    allow(service).to receive(:call).and_raise(Collectibles::AiLookupService::RateLimitError, '429')

    perform_enqueued_jobs { described_class.perform_later(lookup.id) }

    expect(service).to have_received(:call).exactly(4).times
    expect(lookup.reload).to be_failed
    expect(lookup.error_message).to include('saturado')
  end

  it 'no repite una búsqueda ya terminada' do
    lookup.update!(status: :done)
    allow(service).to receive(:call)
    described_class.perform_now(lookup.id)
    expect(service).not_to have_received(:call)
  end
end
```

`spec/jobs/collectibles/ai_lookup_photo_purge_job_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Collectibles::AiLookupPhotoPurgeJob do
  def lookup_created(at)
    travel_to(at) do
      Collectibles::AiLookup.new(user: create(:user, :admin)).tap do |l|
        l.photo.attach(io: File.open(Rails.root.join('spec/fixtures/files/test1.png')), filename: 'a.png', content_type: 'image/png')
        l.save!
      end
    end
  end

  it 'purga la foto de búsquedas con más de 7 días y conserva el registro' do
    old = lookup_created(8.days.ago)
    recent = lookup_created(2.days.ago)

    described_class.perform_now

    expect(old.reload.photo).not_to be_attached
    expect(Collectibles::AiLookup.exists?(old.id)).to be(true)
    expect(recent.reload.photo).to be_attached
  end
end
```

- [ ] **Step 2: Failing request spec**

`spec/requests/admin/collectible_ai_lookups_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin collectible AI lookups', type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user, :admin) }
  let(:png) { Rack::Test::UploadedFile.new(Rails.root.join('spec/fixtures/files/test1.png'), 'image/png') }

  before { sign_in admin }

  describe 'POST create' do
    it 'crea la búsqueda y la encola' do
      expect do
        post admin_collectible_ai_lookups_path, params: { photo: png }
      end.to have_enqueued_job(Collectibles::AiLookupJob)

      expect(response).to have_http_status(:created)
      lookup = Collectibles::AiLookup.last
      expect(response.parsed_body).to eq('id' => lookup.id, 'status_url' => admin_collectible_ai_lookup_path(lookup))
      expect(lookup.user).to eq(admin)
    end

    it 'rechaza un HEIC sin gastar' do
      heic = Rack::Test::UploadedFile.new(StringIO.new('heic'), 'image/heic', original_filename: 'IMG_0001.HEIC')
      expect { post admin_collectible_ai_lookups_path, params: { photo: heic } }.not_to have_enqueued_job

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('JPG, PNG, WEBP o GIF')
    end

    it 'rechaza la petición sin foto' do
      post admin_collectible_ai_lookups_path
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'respeta el límite diario' do
      allow(Collectibles::AiLookup).to receive(:daily_limit_reached?).and_return(true)
      expect { post admin_collectible_ai_lookups_path, params: { photo: png } }.not_to have_enqueued_job

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['error']).to include('límite')
    end

    it 'no deja entrar a un cliente' do
      sign_in create(:user)
      post admin_collectible_ai_lookups_path, params: { photo: png }
      expect(response).to redirect_to(root_path)
      expect(Collectibles::AiLookup.count).to eq(0)
    end
  end

  describe 'GET show' do
    def create_lookup(user)
      Collectibles::AiLookup.new(user: user).tap do |l|
        l.photo.attach(io: File.open(Rails.root.join('spec/fixtures/files/test1.png')), filename: 'a.png', content_type: 'image/png')
        l.save!
      end
    end

    it 'devuelve el estado de una búsqueda propia' do
      lookup = create_lookup(admin)
      lookup.update!(status: :done, result: { 'identification' => { 'brand' => 'Tomica' } })

      get admin_collectible_ai_lookup_path(lookup)
      expect(response.parsed_body).to include('status' => 'done')
      expect(response.parsed_body.dig('result', 'identification', 'brand')).to eq('Tomica')
    end

    it 'no muestra la búsqueda de otro admin' do
      other = create_lookup(create(:user, :admin))
      get admin_collectible_ai_lookup_path(other)
      expect(response).to have_http_status(:not_found)
    end

    it 'reporta como fallida una búsqueda atorada' do
      lookup = create_lookup(admin)
      lookup.update!(status: :running)
      travel 4.minutes do
        get admin_collectible_ai_lookup_path(lookup)
        expect(response.parsed_body['status']).to eq('failed')
      end
    end
  end
end
```

- [ ] **Step 3: Run them to verify they fail**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/jobs/collectibles spec/requests/admin/collectible_ai_lookups_spec.rb`
Expected: FAIL (`uninitialized constant Collectibles::AiLookupJob`, `undefined method admin_collectible_ai_lookups_path`).

- [ ] **Step 4: Jobs**

`app/jobs/collectibles/ai_lookup_job.rb`:
```ruby
# frozen_string_literal: true

module Collectibles
  # Corre AiLookupService en el worker y deja la búsqueda en done o failed.
  # Sólo el 429 se reintenta (5 s, 10 s, 20 s) re-encolando, no con sleep: el
  # worker tiene dos hilos y una espera dormida bloquearía uno.
  class AiLookupJob < ApplicationJob
    queue_as :default

    retry_on Collectibles::AiLookupService::RateLimitError,
             wait: ->(executions) { 5 * (2**(executions - 1)) },
             attempts: 4 do |job, _error|
      lookup = Collectibles::AiLookup.find_by(id: job.arguments.first)
      lookup&.update!(status: :failed, finished_at: Time.current,
                      error_message: 'OpenAI está saturado; intenta de nuevo en unos minutos.')
    end

    discard_on ActiveRecord::RecordNotFound

    def perform(lookup_id)
      lookup = Collectibles::AiLookup.find(lookup_id)
      return if lookup.done? || lookup.failed?

      lookup.update!(status: :running, started_at: lookup.started_at || Time.current,
                     ai_model: Collectibles::AiLookupService::MODEL)
      result = Collectibles::AiLookupService.new(lookup).call
      lookup.update!(status: :done, result: result.data, tokens_input: result.tokens_input,
                     tokens_output: result.tokens_output, web_search_calls: result.web_search_calls,
                     estimated_cost_cents: result.cost_cents, finished_at: Time.current)
    rescue Collectibles::AiLookupService::RateLimitError
      raise
    rescue Collectibles::AiLookupService::Error, Faraday::Error => e
      lookup.update!(status: :failed, finished_at: Time.current,
                     error_message: "No se pudo completar la búsqueda: #{e.message}".truncate(500))
    end
  end
end
```

`app/jobs/collectibles/ai_lookup_photo_purge_job.rb`:
```ruby
# frozen_string_literal: true

module Collectibles
  # Las fotos de búsquedas con IA sólo sirven mientras se da de alta la pieza.
  # A los 7 días se purgan; el registro (resultado y costo) se queda.
  class AiLookupPhotoPurgeJob < ApplicationJob
    queue_as :default

    def perform
      Collectibles::AiLookup.where(created_at: ...7.days.ago)
                            .joins(:photo_attachment)
                            .find_each { |lookup| lookup.photo.purge }
    end
  end
end
```

Add to `config/recurring.yml` under `production:` (after the last existing entry, same indentation):
```yaml
  # Fotos de búsquedas con IA en quick_add: se purgan a los 7 días.
  collectibles_ai_lookup_photo_purge_daily:
    class: Collectibles::AiLookupPhotoPurgeJob
    schedule: "30 4 * * *"
```

- [ ] **Step 5: Controller and routes**

`app/controllers/admin/collectible_ai_lookups_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  # Endpoints JSON de la búsqueda con IA de quick_add: crear (sube la foto y
  # encola) y consultar estado. Cada admin sólo ve sus propias búsquedas.
  class CollectibleAiLookupsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    # POST /admin/collectibles/ai_lookups
    def create
      if Collectibles::AiLookup.daily_limit_reached?
        return render json: { error: "Se alcanzó el límite de #{Collectibles::AiLookup::DAILY_LIMIT} búsquedas con IA por hoy." },
                      status: :too_many_requests
      end

      lookup = Collectibles::AiLookup.new(user: current_user)
      lookup.photo.attach(params[:photo]) if params[:photo].respond_to?(:read)

      if lookup.save
        Collectibles::AiLookupJob.perform_later(lookup.id)
        render json: { id: lookup.id, status_url: admin_collectible_ai_lookup_path(lookup) }, status: :created
      else
        render json: { error: lookup.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    end

    # GET /admin/collectibles/ai_lookups/:id
    def show
      lookup = Collectibles::AiLookup.where(user: current_user).find(params[:id])
      render json: lookup.as_status_json
    end
  end
end
```

In `config/routes.rb`, directly after line 29 (`get 'collectibles/search_products', …`), add:
```ruby
    post 'collectibles/ai_lookups', to: 'collectible_ai_lookups#create', as: :collectible_ai_lookups
    get 'collectibles/ai_lookups/:id', to: 'collectible_ai_lookups#show', as: :collectible_ai_lookup
```

- [ ] **Step 6: Run the specs**

Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/jobs/collectibles spec/requests/admin/collectible_ai_lookups_spec.rb spec/models/collectibles`
Expected: all pass. If `GET show` for another user's lookup raises instead of returning 404 in request specs, check `config.action_dispatch.show_exceptions` in `config/environments/test.rb` and assert with `expect { get ... }.to raise_error(ActiveRecord::RecordNotFound)` only if that is the established pattern in other request specs (`grep -rn "RecordNotFound" spec/requests`).

- [ ] **Step 7: Lint and commit**

Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/jobs/collectibles app/controllers/admin/collectible_ai_lookups_controller.rb config/routes.rb`
```bash
git add app/jobs/collectibles app/controllers/admin/collectible_ai_lookups_controller.rb config/routes.rb config/recurring.yml spec/jobs/collectibles spec/requests/admin/collectible_ai_lookups_spec.rb
git commit -m "feat: endpoints y job de la búsqueda con IA, con purga de fotos"
```

---

### Task 5: Button, polling, form filling and panel on quick_add

**Files:**
- Create: `app/javascript/controllers/collectible_ai_lookup_controller.js`
- Modify: `app/javascript/controllers/index.js` (import + register)
- Modify: `app/views/admin/collectibles/quick_add.html.erb:19` (form `data-controller`) and `:144-155` (photos card + panel)
- Test: `spec/system/admin/collectible_ai_lookup_spec.rb`

**Interfaces:**
- Consumes: `POST admin_collectible_ai_lookups_path` → `{ id, status_url }`; `GET status_url` → `{ id, status, result, error }`; result shape from `AiLookupSchema`.
- Produces: Stimulus identifier `collectible-ai-lookup` with targets `fileInput button status panel`, value `createUrl`.

- [ ] **Step 1: Failing system spec**

`spec/system/admin/collectible_ai_lookup_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin identifica un coleccionable con IA', type: :system do
  let(:admin) { create(:user, :admin) }

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
  ensure
    ActiveJob::Base.queue_adapter = original
  end

  before do
    driven_by :selenium_chrome_headless
    sign_in admin
    allow(OpenAI.configuration).to receive(:access_token).and_return('test-key')
  end

  def answer
    ai_lookup_answer.tap do |a|
      a['prices_world']['listings'].first['title'] = '<img src=x onerror="window.pwned=1">Tomica #23'
    end
  end

  it 'llena sólo los campos vacíos y enseña rareza y precios por mercado' do
    stub_ai_lookup_openai(ai_lookup_openai_response(answer))
    visit admin_collectibles_quick_add_path

    fill_in 'product[brand]', with: 'Mi marca'
    attach_file 'inventory[piece_images][]', Rails.root.join('spec/fixtures/files/test1.png')
    click_button 'Identificar con IA'

    expect(page).to have_css('[data-collectible-ai-lookup-target="panel"]', text: 'Poco común', wait: 15)
    expect(find_field('product[product_name]').value).to eq('Tomica No. 23 Nissan Skyline GT-R R34')
    expect(find_field('product[category]').value).to eq('Autos a escala')
    expect(find_field('product[description]').value).to include('escala 1/62')
    # Lo que el admin ya escribió no se toca; la sugerencia queda en el panel.
    expect(find_field('product[brand]').value).to eq('Mi marca')
    within('[data-collectible-ai-lookup-target="panel"]') do
      expect(page).to have_button('Usar', count: 1)
      expect(page).to have_content('MXN $349 – $420')
      expect(page).to have_content('USD $8.90 – $8.90')
      expect(page).to have_content('¥1,320')
      expect(page).to have_content('<img src=x onerror="window.pwned=1">Tomica #23')
      expect(page).to have_link(href: 'https://articulo.mercadolibre.com.mx/MLM-1')
    end
    expect(page.evaluate_script('window.pwned')).to be_nil
    # Precio y SKU nunca se llenan solos.
    expect(find_field('product[selling_price]').value).to be_blank
    expect(find_field('product[product_sku]').value).to be_blank

    click_button 'Usar'
    expect(find_field('product[brand]').value).to eq('Tomica')
  end

  it 'deshabilita el botón mientras busca' do
    gate = Queue.new
    stub_ai_lookup_openai do
      gate.pop # retiene la respuesta hasta que el spec revise el botón
      ai_lookup_openai_response(answer)
    end
    visit admin_collectibles_quick_add_path
    attach_file 'inventory[piece_images][]', Rails.root.join('spec/fixtures/files/test1.png')
    click_button 'Identificar con IA'

    expect(page).to have_button('Identificar con IA', disabled: true)
    gate << :go
    expect(page).to have_button('Identificar con IA', disabled: false, wait: 15)
    expect(Collectibles::AiLookup.count).to eq(1)
  end

  it 'enseña el error y permite reintentar' do
    stub_ai_lookup_openai { raise Collectibles::AiLookupService::Error, 'Respuesta vacía de OpenAI' }
    visit admin_collectibles_quick_add_path
    attach_file 'inventory[piece_images][]', Rails.root.join('spec/fixtures/files/test1.png')
    click_button 'Identificar con IA'

    expect(page).to have_content('Respuesta vacía de OpenAI', wait: 15)
    expect(page).to have_button('Reintentar')
  end
end
```

Note on "deshabilita el botón": with the `:inline` adapter the job runs inside the `POST`, so the `POST` itself blocks on `gate.pop` — the button is checked while the upload request is still in flight, which is exactly the double-click window.

- [ ] **Step 2: Run it to verify it fails**

Run: `RUN_SYSTEM_SPECS=1 RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/system/admin/collectible_ai_lookup_spec.rb`
Expected: FAIL with `Unable to find button "Identificar con IA"`.

- [ ] **Step 3: View**

In `app/views/admin/collectibles/quick_add.html.erb` line 19, change the form's data to:
```erb
<%= form_with url: admin_collectibles_quick_add_path, method: :post, local: true, html: { class: 'needs-validation' },
              data: { controller: 'collectible-quick-add collectible-ai-lookup',
                      collectible_ai_lookup_create_url_value: admin_collectible_ai_lookups_path } do |f| %>
```

Replace the photos card body (the `<div class="mb-3">` holding `file_field_tag 'inventory[piece_images][]'`) with:
```erb
      <div class="mb-3">
        <label class="form-label">Subir fotos</label>
        <%= file_field_tag 'inventory[piece_images][]', multiple: true, accept: 'image/*', class: 'form-control',
                           data: { collectible_ai_lookup_target: 'fileInput', action: 'change->collectible-ai-lookup#photoChanged' } %>
        <small class="text-muted">Puedes seleccionar múltiples fotos. Estas son específicas de esta pieza, no del producto.</small>
      </div>
      <div class="d-flex align-items-center gap-2">
        <button type="button" class="btn btn-outline-dark" disabled
                data-collectible-ai-lookup-target="button" data-action="collectible-ai-lookup#start">
          <i class="fa-solid fa-wand-magic-sparkles" aria-hidden="true"></i> Identificar con IA
        </button>
        <small class="text-muted" data-collectible-ai-lookup-target="status" role="status"></small>
      </div>
```

Directly after the photos card's closing `</div>` (before the submit buttons), add:
```erb
  <%# Resultado de la IA: lo arma collectible_ai_lookup_controller con textContent. %>
  <div class="card mb-4 d-none border-info" data-collectible-ai-lookup-target="panel" aria-live="polite"></div>
```

Note: the page is a single column, so the panel sits below the photos card rather than beside the form; it is visible next to the submit button where the admin decides.

- [ ] **Step 4: Stimulus controller**

`app/javascript/controllers/collectible_ai_lookup_controller.js`:
```javascript
import { Controller } from "@hotwired/stimulus"

// Identificación con IA en quick_add. Sube la primera foto elegida, sondea el
// estado (JSON + intervalo, el patrón que ya funciona en la app) y, al terminar,
// llena SÓLO los campos vacíos y arma el panel. Todo texto de la IA entra con
// textContent: nunca innerHTML.
const RARITY = { comun: "Común", poco_comun: "Poco común", rara: "Rara", muy_rara: "Muy rara" }
const FIELDS = [
  ["product[product_name]", (r) => r.identification?.product_name, "Nombre"],
  ["product[brand]", (r) => r.identification?.brand, "Marca"],
  ["product[category]", (r) => r.suggested?.category, "Categoría"],
  ["product[description]", (r) => r.suggested?.description_es, "Descripción"],
]
const MAX_WAIT_MS = 4 * 60 * 1000

export default class extends Controller {
  static targets = ["fileInput", "button", "status", "panel"]
  static values = { createUrl: String, interval: { type: Number, default: 3000 } }

  disconnect() { this.stopPolling() }

  photoChanged() {
    if (!this.running) this.buttonTarget.disabled = !this.firstPhoto()
  }

  firstPhoto() { return this.fileInputTarget.files?.[0] }

  async start() {
    const photo = this.firstPhoto()
    if (!photo || this.running) return
    this.setRunning(true, "Buscando… (~30–60 s)")
    this.hidePanel()

    const body = new FormData()
    body.append("photo", photo)
    try {
      const res = await fetch(this.createUrlValue, {
        method: "POST",
        body,
        headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken() },
      })
      const json = await res.json().catch(() => ({}))
      if (!res.ok) return this.showError(json.error || "No se pudo iniciar la búsqueda.")
      this.poll(json.status_url)
    } catch (_e) {
      this.showError("No se pudo conectar con el servidor.")
    }
  }

  poll(url) {
    const startedAt = Date.now()
    this.stopPolling()
    this.timer = window.setInterval(async () => {
      if (Date.now() - startedAt > MAX_WAIT_MS) return this.showError("La búsqueda tardó demasiado. Intenta de nuevo.")
      try {
        const res = await fetch(url, { headers: { Accept: "application/json" } })
        const state = await res.json()
        if (state.status === "done") this.finish(state.result)
        else if (state.status === "failed") this.showError(state.error || "La búsqueda falló.")
      } catch (_e) { /* un tropiezo de red no termina la búsqueda; el tope de tiempo sí */ }
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.timer) window.clearInterval(this.timer)
    this.timer = null
  }

  finish(result) {
    this.stopPolling()
    this.setRunning(false, "Listo. Revisa los datos antes de guardar.")
    const suggestions = this.fillEmptyFields(result)
    this.renderPanel(result, suggestions)
  }

  fillEmptyFields(result) {
    const pending = []
    FIELDS.forEach(([name, pick, label]) => {
      const value = pick(result)
      const field = this.element.querySelector(`[name="${name}"]`)
      if (!value || !field) return
      if (field.value.trim() === "") field.value = value
      else if (field.value.trim() !== value) pending.push({ field, value, label })
    })
    return pending
  }

  renderPanel(r, suggestions) {
    const panel = this.panelTarget
    panel.replaceChildren()
    const header = this.el("div", "card-header bg-info-subtle fw-semibold", "Resultado de la IA")
    const body = this.el("div", "card-body small")
    panel.append(header, body)

    const id = r.identification || {}
    const conf = Math.round((id.confidence || 0) * 100)
    body.append(this.el("p", "mb-1", `${id.product_name || "Sin identificar"} · confianza ${conf}%`))
    if (conf < 60) body.append(this.el("div", "alert alert-warning py-1 mb-2", "Confianza baja: verifica el modelo."))
    const details = [id.brand, id.series, id.model_code, id.scale, id.year_or_edition].filter(Boolean).join(" · ")
    if (details) body.append(this.el("p", "text-muted mb-2", details))

    const launch = this.el("p", "mb-1", `Lanzamiento: ${r.launch_date?.value || "sin dato"}`)
    if (r.launch_date?.source_url) launch.append(" ", this.link(r.launch_date.source_url, "fuente"))
    body.append(launch)

    body.append(this.el("p", "mb-1", `Rareza: ${RARITY[r.rarity?.level] || "sin dato"}`))
    const reasons = this.el("ul", "mb-2")
    ;(r.rarity?.reasons || []).forEach((reason) => reasons.append(this.el("li", "", reason)))
    body.append(reasons)

    const row = this.el("div", "row g-3")
    row.append(this.market("🇲🇽 México", r.prices_mx, "MXN"), this.market("🌎 Mundial", r.prices_world, "USD"))
    body.append(row)

    suggestions.forEach(({ field, value, label }) => {
      const line = this.el("div", "d-flex align-items-start gap-2 mt-2")
      const button = this.el("button", "btn btn-sm btn-outline-primary", "Usar")
      button.type = "button"
      button.addEventListener("click", () => { field.value = value; line.remove() })
      line.append(button, this.el("span", "", `${label}: ${value}`))
      body.append(line)
    })

    if ((r.warnings || []).length) {
      const warn = this.el("ul", "text-warning-emphasis mt-2 mb-0")
      r.warnings.forEach((w) => warn.append(this.el("li", "", w)))
      body.append(warn)
    }
    panel.classList.remove("d-none")
  }

  market(title, data, currency) {
    const col = this.el("div", "col-12 col-md-6")
    col.append(this.el("div", "fw-semibold", title))
    if (!data) {
      col.append(this.el("div", "text-muted", "Sin datos en sitios confiables"))
      return col
    }
    col.append(this.el("div", "mb-1", `${currency} ${this.money(data.min)} – ${this.money(data.max)}`))
    const list = this.el("ul", "list-unstyled mb-0")
    data.listings.forEach((l) => {
      const item = this.el("li", "mb-1")
      item.append(this.link(l.url, l.title), ` · ${l.price_original} · ${l.sold ? "vendido" : "en venta"}`)
      list.append(item)
    })
    col.append(list)
    return col
  }

  showError(message) {
    this.stopPolling()
    this.setRunning(false, "")
    const panel = this.panelTarget
    panel.replaceChildren()
    const body = this.el("div", "card-body small d-flex align-items-center gap-2")
    const retry = this.el("button", "btn btn-sm btn-outline-danger", "Reintentar")
    retry.type = "button"
    retry.addEventListener("click", () => this.start())
    body.append(this.el("span", "text-danger", message), retry)
    panel.append(body)
    panel.classList.remove("d-none")
  }

  setRunning(running, text) {
    this.running = running
    this.buttonTarget.disabled = running || !this.firstPhoto()
    this.statusTarget.textContent = text
  }

  hidePanel() { this.panelTarget.classList.add("d-none") }

  money(n) { return `$${Number(n).toLocaleString("en-US", { minimumFractionDigits: n % 1 ? 2 : 0, maximumFractionDigits: 2 })}` }

  link(url, text) {
    const a = this.el("a", "", text)
    if (/^https?:\/\//.test(url)) a.href = url
    a.target = "_blank"
    a.rel = "noopener noreferrer"
    return a
  }

  el(tag, className, text) {
    const node = document.createElement(tag)
    if (className) node.className = className
    if (text !== undefined) node.textContent = text
    return node
  }

  csrfToken() { return document.querySelector('meta[name="csrf-token"]')?.content }
}
```

Check the money format against the spec: `money(8.9)` → `"$8.90"` (8.9 % 1 ≠ 0 → 2 decimals), `money(349)` → `"$349"`, `money(420)` → `"$420"`. So the panel shows `MXN $349 – $420` and `USD $8.90 – $8.90`.

- [ ] **Step 5: Register the controller**

In `app/javascript/controllers/index.js` add, next to the other imports:
```javascript
import CollectibleAiLookupController from "./collectible_ai_lookup_controller"
```
and next to the other registrations:
```javascript
application.register("collectible-ai-lookup", CollectibleAiLookupController)
```

- [ ] **Step 6: Run the system spec**

Run: `RUN_SYSTEM_SPECS=1 RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/system/admin/collectible_ai_lookup_spec.rb`
Expected: 3 examples, 0 failures. If the inline adapter does not reach the OpenAI stub because the app server runs in another thread, keep the stub (RSpec mocks are process-wide for `allow(...)` on classes) and inspect `log/test.log` for the job's error before changing approach.

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/collectible_ai_lookup_controller.js app/javascript/controllers/index.js app/views/admin/collectibles/quick_add.html.erb spec/system/admin/collectible_ai_lookup_spec.rb
git commit -m "feat: botón Identificar con IA en quick_add con panel de rareza y precios"
```

---

### Task 6: Full verification

**Files:** none new.

- [ ] **Step 1: Existing quick_add specs still pass**

Run: `RUN_SYSTEM_SPECS=1 RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec $(grep -rlE "quick_add|collectibles" spec)`
Expected: 0 failures.

- [ ] **Step 2: Full suite**

Run: `RUN_SYSTEM_SPECS=1 RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec`
Expected: 0 failures. Any failure stops the branch; debug it before proceeding.

- [ ] **Step 3: Lint the app code**

Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app config/routes.rb`
Expected: no offenses.

- [ ] **Step 4: Refresh the knowledge graph**

Run: `graphify update .`

- [ ] **Step 5: Post-deploy manual check (after merge and `git push heroku main`)**

On `https://pasatiempos.com.mx/admin/collectibles/quick_add`, choose a real photo of a known piece, click "Identificar con IA" and confirm: empty fields fill, both markets show listings whose links open, cost is recorded (`heroku run rails runner 'p Collectibles::AiLookup.last.slice(:status, :estimated_cost_cents, :web_search_calls)'`). Never print `OPENAI_API_KEY` or any environment listing.
