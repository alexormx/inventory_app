# frozen_string_literal: true

FactoryBot.define do
  factory :shipping_method do
    sequence(:name) { |n| "Método de Envío #{n}" }
    sequence(:code) { |n| "shipping_#{n}" }
    description { "Descripción del método de envío" }
    base_cost { 0 }
    active { true }
    position { 0 }

    trait :standard do
      name { "Envío Estándar" }
      code { "standard" }
      description { "Entrega en 3-5 días hábiles" }
      base_cost { 0 }
    end

    trait :express do
      name { "Envío Exprés" }
      code { "express" }
      description { "Entrega en 1-2 días hábiles" }
      base_cost { 149 }
    end

    trait :pickup do
      name { "Recoger en Tienda" }
      code { "pickup" }
      description { "Sin costo de envío" }
      base_cost { 0 }
    end

    trait :inactive do
      active { false }
    end
  end
end
