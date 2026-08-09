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
end
