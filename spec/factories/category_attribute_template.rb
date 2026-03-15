# frozen_string_literal: true

FactoryBot.define do
  factory :category_attribute_template do
    category { "diecast" }
    active { true }
    attributes_schema do
      [
        { "key" => "color", "label" => "Color", "type" => "string", "required" => true, "position" => 1, "example" => "Azul metálico" },
        { "key" => "linea", "label" => "Línea", "type" => "string", "required" => true, "position" => 2, "example" => "" },
        { "key" => "marca", "label" => "Marca", "type" => "string", "required" => true, "position" => 3, "example" => "Takara Tomy" },
        { "key" => "escala", "label" => "Escala", "type" => "string", "required" => true, "position" => 4, "example" => "1:64" },
        { "key" => "modelo", "label" => "Modelo", "type" => "string", "required" => true, "position" => 5, "example" => "" },
        { "key" => "material", "label" => "Material", "type" => "string", "required" => true, "position" => 6, "example" => "" },
        { "key" => "apertura", "label" => "Apertura", "type" => "boolean", "required" => false, "position" => 7, "example" => "false" },
        { "key" => "suspension", "label" => "Suspensión", "type" => "boolean", "required" => false, "position" => 8, "example" => "true" }
      ]
    end

    trait :inactive do
      active { false }
    end
  end
end
