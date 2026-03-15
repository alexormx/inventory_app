# frozen_string_literal: true

FactoryBot.define do
  factory :product_description_draft do
    association :product
    status { "queued" }

    trait :generating do
      status { "generating" }
    end

    trait :draft_generated do
      status { "draft_generated" }
      draft_content { "Réplica a escala del modelo original. Fabricado en die-cast metálico con piezas plásticas." }
      draft_attributes do
        {
          "color" => "Negro",
          "linea" => "Tomica (Serie regular)",
          "marca" => "Takara Tomy",
          "escala" => "1:70",
          "modelo" => "Toyota Hilux (No.67)",
          "origen" => "Japón",
          "apertura" => "false",
          "material" => "Die-cast metálico con piezas plásticas",
          "suspension" => "true",
          "edad_recomendada" => "+3",
          "fecha_de_lanzamiento" => "2021-09-18"
        }
      end
      structured_output do
        {
          "product_name" => "067 Toyota Hilux",
          "description_es" => "Réplica a escala del modelo original.",
          "highlights" => ["Modelo numerado #067"],
          "attributes" => { "color" => "Negro" },
          "seo_keywords" => ["tomica hilux"],
          "warnings" => [],
          "confidence_score" => 0.9
        }
      end
      warnings { [] }
      confidence_score { 0.9 }
      ai_provider { "openai" }
      ai_model { "gpt-4o-mini" }
      prompt_version { "v1" }
      tokens_input { 500 }
      tokens_output { 300 }
      estimated_cost_cents { 1 }
      generated_at { Time.current }
    end

    trait :published do
      draft_generated
      status { "published" }
      published_at { Time.current }
      association :published_by, factory: :user
    end

    trait :failed do
      status { "failed" }
      error_message { "OpenAI API error: rate limit exceeded" }
      generated_at { Time.current }
    end

    trait :rejected do
      draft_generated
      status { "rejected" }
    end
  end
end
