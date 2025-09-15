# frozen_string_literal: true

FactoryBot.define do
  sequence(:sku_seq)       { |n| "SKU-#{n.to_s.rjust(5, '0')}" }
  sequence(:whatsapp_seq)  { |n| "WGT#{n.to_s.rjust(3, '0')}-#{SecureRandom.hex(2)}" }

  factory :product do
    product_sku     { generate(:sku_seq) }
    product_name    { 'Sample Product' }
    brand           { 'Tomica' }

    # Category/status – safe defaults
    category        { 'diecast' }
    status { 'active' }

    # Prices & discounts – keep valid relationship
    minimum_price   { 99.99 }
    selling_price   { 199.99 }
    maximum_discount { 0 } # ✅ required numeric

    # Inventory-ish
    reorder_point { 0 }
    backorder_allowed   { false }
    preorder_available  { false }

    # Dimensions
    weight_gr       { 100 }
    length_cm       { 16 }
    width_cm        { 4 }
    height_cm       { 4 }

    # Identifiers
  whatsapp_code   { generate(:whatsapp_seq) } # ✅ required & unique (adds random hex to avoid collisions in non-isolated tests)

    custom_attributes { {} }

    transient do
      skip_seed_inventory { false }
      seed_inventory_count { 5 }
    end

    after(:create) do |product, evaluator|
      # Attach a couple of images (silent rescue if missing fixtures to avoid noisy failures)
      begin
        file1 = Rails.root.join('spec/fixtures/files/test1.png')
        file2 = Rails.root.join('spec/fixtures/files/test2.png')
        if File.exist?(file1)
          product.product_images.attach(
            io: File.open(file1),
            filename: 'test1.png',
            content_type: 'image/png'
          )
        end
        if File.exist?(file2)
          product.product_images.attach(
            io: File.open(file2),
            filename: 'test2.png',
            content_type: 'image/png'
          )
        end
      rescue StandardError => e
        Rails.logger.debug { "[FactoryBot] Skipping image attach for product: #{e.class}: #{e.message}" }
      end
      unless evaluator.skip_seed_inventory
        # Ensure sufficient available inventory units so cart specs (which update quantities) pass.
        needed = evaluator.seed_inventory_count
        current = product.inventories.available.count
        if current < needed
          (needed - current).times do
            Inventory.create!(product: product, purchase_cost: product.minimum_price, status: :available)
          end
        end
      end
    end
  end
end
