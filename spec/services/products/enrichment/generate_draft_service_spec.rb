# frozen_string_literal: true

require "rails_helper"

RSpec.describe Products::Enrichment::GenerateDraftService do
  let(:product) { create(:product, skip_seed_inventory: true, category: "diecast") }
  let(:draft) { create(:product_description_draft, product: product, status: :queued) }
  let!(:template) { create(:category_attribute_template, category: "diecast") }

  let(:openai_response) do
    {
      "choices" => [
        {
          "message" => {
            "content" => {
              "product_name" => "067 Toyota Hilux",
              "description_es" => <<~TEXT,
                El Toyota Hilux de Tomica transmite desde el primer vistazo ese carácter robusto y confiable que convirtió a esta pickup en un referente. Su presencia compacta, el acabado cuidado y la silueta reconocible lo vuelven una pieza muy atractiva para quienes disfrutan exhibir modelos con personalidad propia dentro de una colección diecast.

                Esta miniatura resulta especialmente llamativa para vitrinas temáticas de utilitarios, vehículos japoneses o piezas numeradas de la marca. Es una opción con gran valor visual para regalar, complementar una colección de Tomica o sumar un modelo que combina identidad clásica, detalle y encanto coleccionable en un formato fácil de apreciar.
              TEXT
              "highlights" => ["Modelo numerado #067", "Die-cast metálico"],
              "attributes" => {
                "color" => "Blanco",
                "escala" => "1:64",
                "marca" => "Tomica",
                "modelo" => "Toyota Hilux",
                "material" => "Die-cast",
                "apertura" => "false",
                "suspension" => "sí"
              },
              "seo_keywords" => ["tomica", "hilux", "diecast"],
              "warnings" => ["Fecha de lanzamiento estimada"],
              "confidence_score" => 0.85
            }.to_json
          }
        }
      ],
      "usage" => {
        "prompt_tokens" => 500,
        "completion_tokens" => 300
      }
    }
  end

  let(:openai_client) { instance_double(OpenAI::Client) }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(openai_client)
    allow(openai_client).to receive(:chat).and_return(openai_response)
  end

  subject(:service) { described_class.new(draft) }

  describe "#call" do
    it "transitions draft from queued to draft_generated" do
      service.call
      draft.reload
      expect(draft.status).to eq("draft_generated")
    end

    it "fills in the draft content" do
      service.call
      draft.reload
      expect(draft.draft_content).to include("Toyota Hilux")
    end

    it "normalizes and stores attributes" do
      service.call
      draft.reload
      expect(draft.draft_attributes["color"]).to eq("Blanco")
      expect(draft.draft_attributes["suspension"]).to eq("true") # "sí" → "true"
      expect(draft.draft_attributes["apertura"]).to eq("false")
    end

    it "records AI metadata" do
      service.call
      draft.reload
      expect(draft.ai_provider).to eq("openai")
      expect(draft.ai_model).to eq("gpt-4.1-mini")
      expect(draft.prompt_version).to eq("v8")
      expect(draft.tokens_input).to eq(500)
      expect(draft.tokens_output).to eq(300)
      expect(draft.generated_at).to be_present
    end

    it "stores structured output" do
      service.call
      draft.reload
      expect(draft.structured_output).to be_a(Hash)
      expect(draft.structured_output["product_name"]).to eq("067 Toyota Hilux")
    end

    it "stores warnings" do
      service.call
      draft.reload
      expect(draft.warnings).to include("Fecha de lanzamiento estimada")
    end

    it "stores confidence score" do
      service.call
      draft.reload
      expect(draft.confidence_score).to eq(0.85)
    end

    it "estimates the real cost in cents with gpt-4.1-mini prices" do
      openai_response["usage"] = { "prompt_tokens" => 1_000_000, "completion_tokens" => 500_000 }
      service.call
      # 1M × $0.40 + 0.5M × $1.60 = $1.20 → 120 centavos
      expect(draft.reload.estimated_cost_cents).to eq(120)
    end

    it "stores source snapshot" do
      service.call
      draft.reload
      expect(draft.source_snapshot).to be_a(Hash)
      expect(draft.source_snapshot["product_id"]).to eq(product.id)
    end

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
  end

  context "when OpenAI returns a valid single-paragraph description" do
    let(:openai_response) do
      {
        "choices" => [
          {
            "message" => {
              "content" => {
                "product_name" => "067 Toyota Hilux",
                "description_es" =>
                  "Modelo Tomica del Toyota Hilux en color blanco, fabricado en escala 1:64 con " \
                  "cuerpo die-cast y piezas plásticas. Es una opción adecuada para coleccionistas " \
                  "de pickups y vehículos japoneses que buscan modelos compactos y bien detallados.",
                "highlights" => ["Modelo numerado #067"],
                "attributes" => { "color" => "Blanco" },
                "seo_keywords" => ["tomica", "hilux"],
                "warnings" => [],
                "confidence_score" => 0.8
              }.to_json
            }
          }
        ],
        "usage" => {}
      }
    end

    it "accepts a concise single paragraph" do
      service.call
      draft.reload
      expect(draft.status).to eq("draft_generated")
      expect(draft.draft_content).to include("escala 1:64")
    end
  end

  describe "identificadores internos en la respuesta" do
    let(:product) do
      create(:product, skip_seed_inventory: true, category: "diecast", product_sku: "PAS-TOM-0042",
                       supplier_product_code: "TKT-98765", barcode: "4904810742241")
    end

    before do
      content = JSON.parse(openai_response.dig("choices", 0, "message", "content"))
      content["description_es"] += "\n\nSu código de proveedor es TKT-98765."
      content["highlights"] = ["Modelo numerado #067", "SKU PAS-TOM-0042", "Código de barras 4904810742241"]
      content["seo_keywords"] = ["tomica", "4904810742241"]
      openai_response["choices"][0]["message"]["content"] = content.to_json
    end

    it "los quita de la descripción, las características y las palabras clave, y lo avisa" do
      service.call
      draft.reload
      expect(draft.draft_content).not_to include("TKT-98765")
      expect(draft.structured_output["highlights"]).to eq(["Modelo numerado #067"])
      expect(draft.structured_output["seo_keywords"]).to eq(["tomica"])
      expect(draft.warnings.join).to include("identificadores internos")
    end
  end

  describe "error handling" do
    context "when OpenAI returns empty content" do
      let(:openai_response) do
        { "choices" => [{ "message" => { "content" => "" } }], "usage" => {} }
      end

      it "marks draft as failed" do
        expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::GenerationError)
        draft.reload
        expect(draft.status).to eq("failed")
        expect(draft.error_message).to include("Empty response")
      end
    end

    context "when OpenAI returns invalid JSON" do
      let(:openai_response) do
        { "choices" => [{ "message" => { "content" => "not json" } }], "usage" => {} }
      end

      it "marks draft as failed with parse error" do
        expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::GenerationError)
        draft.reload
        expect(draft.status).to eq("failed")
        expect(draft.error_message).to include("parse")
      end
    end

    context "when OpenAI response lacks description_es" do
      let(:openai_response) do
        { "choices" => [{ "message" => { "content" => '{"foo":"bar"}' } }], "usage" => {} }
      end

      it "marks draft as failed with structure error" do
        expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::GenerationError)
        draft.reload
        expect(draft.status).to eq("failed")
        expect(draft.error_message).to include("description_es")
      end
    end

    context "when OpenAI returns a description with old visible headings" do
      let(:openai_response) do
        {
          "choices" => [
            {
              "message" => {
                "content" => {
                  "product_name" => "067 Toyota Hilux",
                  "description_es" => <<~TEXT,
                    Resumen:
                    Réplica a escala del Toyota Hilux con gran presencia visual para colección.

                    Historia y contexto:
                    Una pickup icónica llevada a formato coleccionable.
                  TEXT
                  "highlights" => ["Modelo numerado #067"],
                  "attributes" => { "color" => "Blanco" },
                  "seo_keywords" => ["tomica"],
                  "warnings" => [],
                  "confidence_score" => 0.8
                }.to_json
              }
            }
          ],
          "usage" => {}
        }
      end

      it "marks draft as failed with structure error" do
        expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::GenerationError)
        draft.reload
        expect(draft.status).to eq("failed")
        expect(draft.error_message).to include("without headings or null values")
      end
    end

    context "when OpenAI returns null inside the description" do
      let(:openai_response) do
        {
          "choices" => [
            {
              "message" => {
                "content" => {
                  "product_name" => "067 Toyota Hilux",
                  "description_es" => <<~TEXT,
                    El Toyota Hilux de Tomica destaca por su presencia robusta y su atractivo para colección. Escala: null y material confirmado por revisar.

                    Es una pieza interesante para vitrinas temáticas y para quienes buscan pickups icónicas en formato compacto.
                  TEXT
                  "highlights" => ["Modelo numerado #067"],
                  "attributes" => { "color" => "Blanco", "escala" => "null" },
                  "seo_keywords" => ["tomica"],
                  "warnings" => [],
                  "confidence_score" => 0.8
                }.to_json
              }
            }
          ],
          "usage" => {}
        }
      end

      it "marks draft as failed" do
        expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::GenerationError)
        draft.reload
        expect(draft.status).to eq("failed")
        expect(draft.error_message).to include("without headings or null values")
      end
    end

    context "when OpenAI returns null only in attributes" do
      let(:openai_response) do
        {
          "choices" => [
            {
              "message" => {
                "content" => {
                  "product_name" => "067 Toyota Hilux",
                  "description_es" => <<~TEXT,
                    El Toyota Hilux de Tomica ofrece una presencia fuerte y un estilo reconocible que luce muy bien en cualquier vitrina. Su diseño utilitario y el encanto clásico de la marca lo convierten en una pieza atractiva para coleccionistas que buscan modelos con identidad.

                    Además de su valor visual, es una miniatura fácil de integrar en colecciones de pickups, vehículos japoneses o lanzamientos numerados. Funciona muy bien como regalo o como incorporación especial para quien disfruta piezas compactas con carácter y buen nivel de detalle.
                  TEXT
                  "highlights" => ["Modelo numerado #067"],
                  "attributes" => { "color" => "Blanco", "escala" => "null", "apertura" => "false" },
                  "seo_keywords" => ["tomica"],
                  "warnings" => ["Escala no confirmada"],
                  "confidence_score" => 0.8
                }.to_json
              }
            }
          ],
          "usage" => {}
        }
      end

      it "succeeds and normalizes null attributes" do
        service.call
        draft.reload
        expect(draft.status).to eq("draft_generated")
        expect(draft.draft_content).not_to include("null")
        expect(draft.draft_attributes["escala"]).to be_nil
      end
    end

    context "when OpenAI client raises an error" do
      before do
        allow(openai_client).to receive(:chat).and_raise(Faraday::TimeoutError.new("timeout"))
      end

      it "marks draft as failed and raises TransientError" do
        expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::TransientError)
        draft.reload
        expect(draft.status).to eq("failed")
        expect(draft.error_message).to include("timeout")
      end
    end

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
  end

  describe "producto sin plantilla de categoría" do
    let(:product) { create(:product, skip_seed_inventory: true, category: "Cars & Bikes") }

    before do
      content = JSON.parse(openai_response.dig("choices", 0, "message", "content"))
      content["attributes"] = [{ "key" => "color", "value" => "Rojo" }, { "key" => "escala", "value" => nil }]
      openai_response["choices"][0]["message"]["content"] = content.to_json
    end

    it "convierte la lista de pares en los atributos de siempre" do
      service.call
      expect(draft.reload.draft_attributes).to eq("color" => "Rojo", "escala" => nil)
    end
  end

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

  describe "costo de un intento fallido" do
    it "registra tokens y costo aunque la respuesta no sirva (OpenAI sí la cobró)" do
      openai_response["choices"][0]["message"]["content"] = "{roto"
      openai_response["usage"] = { "prompt_tokens" => 1_000_000, "completion_tokens" => 500_000 }
      expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::InvalidResponseError)
      draft.reload
      expect(draft.status).to eq("failed")
      expect([draft.tokens_input, draft.tokens_output, draft.estimated_cost_cents]).to eq([1_000_000, 500_000, 120])
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
end
