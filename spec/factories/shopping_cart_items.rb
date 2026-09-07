# frozen_string_literal: true

FactoryBot.define do
  factory :shopping_cart_item do
    association :shopping_cart, strategy: :create
    # :create, not the parent's own strategy: product_reference is copied
    # from product.id below, so the product must actually be persisted first.
    association :product, strategy: :create, skip_seed_inventory: true
    condition { 'brand_new' }
    quantity { 1 }

    after(:build) do |item|
      item.product_reference ||= item.product&.id
      item.product_name_snapshot ||= item.product&.product_name
    end
  end
end
