# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Products catalog inventory queries', type: :request do
  def capture_catalog_queries(&block)
    queries = []
    callback = lambda do |_name, _started, _finished, _unique_id, payload|
      sql = payload[:sql].to_s.squish
      next if payload[:cached]
      next if %w[SCHEMA CACHE].include?(payload[:name])
      next if sql.match?(/\A(?:BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)\b/i)

      queries << sql
    end

    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &block)
    queries
  end

  it 'uses one grouped transit count and no per-product transit counts for the visible page' do
    products = create_list(:product, 12)

    queries = capture_catalog_queries { get catalog_path }
    transit_counts = queries.select do |sql|
      sql.match?(/\ASELECT COUNT\(\*\)(?: AS .+?)? FROM "inventories"/i) &&
        sql.include?('"inventories"."sale_order_id" IS NULL') &&
        sql.exclude?('"inventories"."inventory_location_id" IS NOT NULL')
    end
    grouped_counts = transit_counts.select { |sql| sql.include?('GROUP BY "inventories"."product_id"') }
    individual_counts = transit_counts - grouped_counts

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(*products.map(&:product_name))
    expect(individual_counts).to be_empty
    expect(grouped_counts.size).to eq(1)
  end

  it 'uses one canonical grouped on-hand count for the visible page' do
    create_list(:product, 12)

    queries = capture_catalog_queries { get catalog_path }
    on_hand_counts = queries.select do |sql|
      sql.match?(/\ASELECT COUNT\(\*\)/i) &&
        sql[/\bFROM "[^"]+"/] == 'FROM "inventories"' &&
        sql.include?('"inventories"."sale_order_id" IS NULL') &&
        sql.include?('"inventories"."inventory_location_id" IS NOT NULL')
    end
    grouped_counts = on_hand_counts.select { |sql| sql.include?('GROUP BY "inventories"."product_id"') }

    expect(response).to have_http_status(:ok)
    expect(grouped_counts.size).to eq(1)
    expect(on_hand_counts).to eq(grouped_counts)
  end

  it 'does not advertise an unlocated related product as on-hand' do
    product = create(:product, category: 'Autos', brand: 'Tomica')
    related = create(:product, skip_seed_inventory: true, category: 'Autos', brand: 'Tomica')
    create(:inventory, product: related, status: :available, inventory_location: nil)
    related.update_columns(status: 'active', auto_paused: false, auto_paused_at: nil)

    get product_path(product)

    document = Nokogiri::HTML(response.body)
    related_name = document.at_css("h6[title='#{related.product_name}']")
    related_item = related_name.ancestors('.related-product-item').first
    expect(related_item.text).not_to include('En stock')
  end

  it 'does not render stale product detail Stimulus identifiers' do
    product = create(:product)

    get product_path(product)

    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.css('[data-controller~="product-conditions"]')).to be_empty
    expect(document.css('[data-controller~="productMeta"]')).to be_empty
    expect(document.css('[data-controller~="product-meta"]')).to be_empty
  end
end
