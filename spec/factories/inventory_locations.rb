# frozen_string_literal: true

FactoryBot.define do
  factory :inventory_location do
    sequence(:name) { |n| "Location #{n}" }
    sequence(:code) { |n| "LOC-#{n}" }
    location_type { 'warehouse' }
    active { true }
    position { 0 }

    trait :warehouse do
      location_type { 'warehouse' }
      sequence(:name) { |n| "Bodega #{('A'.ord + n - 1).chr}" }
    end

    trait :zone do
      location_type { 'zone' }
      sequence(:name) { |n| "Zona #{n}" }
    end

    trait :section do
      location_type { 'section' }
      sequence(:name) { |n| "Sección #{n}" }
    end

    trait :aisle do
      location_type { 'aisle' }
      sequence(:name) { |n| "Pasillo #{n}" }
    end

    trait :rack do
      location_type { 'rack' }
      sequence(:name) { |n| "Estante #{n}" }
    end

    trait :shelf do
      location_type { 'shelf' }
      sequence(:name) { |n| "Anaquel #{n}" }
    end

    trait :level do
      location_type { 'level' }
      sequence(:name) { |n| "Nivel #{n}" }
    end

    trait :bin do
      location_type { 'bin' }
      sequence(:name) { |n| "Contenedor #{n}" }
    end

    trait :inactive do
      active { false }
    end

    # Create with parent
    trait :with_parent do
      association :parent, factory: [:inventory_location, :warehouse]
      location_type { 'section' }
    end
  end
end
