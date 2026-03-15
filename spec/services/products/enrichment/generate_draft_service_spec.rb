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
                Resumen:
                Réplica a escala del Toyota Hilux fabricada por Tomica, ideal para colección y exhibición por su acabado detallado y su perfil utilitario reconocible.

                Ficha del modelo:
                - Marca: Tomica
                - Modelo: Toyota Hilux
                - Escala: 1:64
                - Material: Die-cast

                Puntos destacados:
                - Modelo numerado #067.
                - Carrocería con presencia robusta y proporciones compactas.
                - Pieza ideal para vitrinas temáticas de pickups y utilitarios.

                Historia y contexto:
                La Toyota Hilux es una de las pickups más conocidas a nivel mundial, apreciada por su resistencia y uso versátil. Esta miniatura traslada esa identidad a un formato coleccionable accesible y fácil de exhibir.

                Cierre:
                Una excelente opción para coleccionistas de Tomica y para quienes buscan sumar una pickup icónica a su colección de autos a escala.
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
      expect(draft.ai_model).to eq("gpt-4o-mini")
      expect(draft.prompt_version).to eq("v2")
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

    it "estimates cost" do
      service.call
      draft.reload
      expect(draft.estimated_cost_cents).to be_present
      expect(draft.estimated_cost_cents).to be >= 0
    end

    it "stores source snapshot" do
      service.call
      draft.reload
      expect(draft.source_snapshot).to be_a(Hash)
      expect(draft.source_snapshot["product_id"]).to eq(product.id)
    end

    it "calls OpenAI with correct parameters" do
      service.call
      expect(openai_client).to have_received(:chat).with(
        parameters: hash_including(
          model: "gpt-4o-mini",
          temperature: 0.4,
          response_format: { type: "json_object" },
          max_tokens: 2000
        )
      )
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

    context "when OpenAI returns an unstructured description" do
      let(:openai_response) do
        {
          "choices" => [
            {
              "message" => {
                "content" => {
                  "product_name" => "067 Toyota Hilux",
                  "description_es" => "Réplica a escala 1:64 del Toyota Hilux fabricada por Tomica en un solo párrafo sin bloques ni viñetas.",
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
        expect(draft.error_message).to include("structured sections")
      end
    end

    context "when OpenAI client raises an error" do
      before do
        allow(openai_client).to receive(:chat).and_raise(Faraday::TimeoutError.new("timeout"))
      end

      it "marks draft as failed and re-raises as GenerationError" do
        expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::GenerationError)
        draft.reload
        expect(draft.status).to eq("failed")
        expect(draft.error_message).to include("timeout")
      end
    end

    context "when OpenAI returns 429 rate limit" do
      before do
        stub_const("Products::Enrichment::GenerateDraftService::MAX_RETRIES", 1)
        stub_const("Products::Enrichment::GenerateDraftService::BASE_WAIT_SECS", 0)
        allow(openai_client).to receive(:chat).and_raise(
          Faraday::TooManyRequestsError.new(status: 429)
        )
      end

      it "raises RateLimitError after exhausting retries" do
        expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::RateLimitError)
        draft.reload
        expect(draft.status).to eq("failed")
        expect(draft.error_message).to include("rate limit")
      end

      it "retries before failing" do
        expect { service.call }.to raise_error(Products::Enrichment::GenerateDraftService::RateLimitError)
        # 1 initial + 1 retry = 2 calls
        expect(openai_client).to have_received(:chat).twice
      end
    end

    context "when OpenAI 429 resolves on retry" do
      before do
        stub_const("Products::Enrichment::GenerateDraftService::BASE_WAIT_SECS", 0)
        call_count = 0
        allow(openai_client).to receive(:chat) do
          call_count += 1
          if call_count == 1
            raise Faraday::TooManyRequestsError.new(status: 429)
          else
            openai_response
          end
        end
      end

      it "succeeds after transient 429" do
        service.call
        draft.reload
        expect(draft.status).to eq("draft_generated")
        expect(openai_client).to have_received(:chat).twice
      end
    end
  end
end
