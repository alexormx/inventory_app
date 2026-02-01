# frozen_string_literal: true

FactoryBot.define do
  factory :location_type do
    sequence(:name) { |n| "Tipo #{n}" }
    sequence(:code) { |n| "type_#{n}" }
    icon { 'bi-box' }
    color { 'primary' }
    sequence(:position) { |n| n }
    active { true }

    trait :inactive do
      active { false }
    end

    trait :warehouse do
      name { 'Bodega' }
      code { 'warehouse' }
      icon { 'bi-building' }
      color { 'primary' }
      position { 0 }
    end

    trait :zone do
      name { 'Zona' }
      code { 'zone' }
      icon { 'bi-grid-3x3-gap' }
      color { 'info' }
      position { 1 }
    end

    trait :shelf do
      name { 'Estante' }
      code { 'shelf' }
      icon { 'bi-bookshelf' }
      color { 'danger' }
      position { 4 }
    end
  end
end
