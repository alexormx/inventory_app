# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dashboard::WorstProductsBuilder do
  describe '#call' do
    it 'uses average purchase cost for cogs and includes preparing orders' do
      product = create(:product, average_purchase_cost: 50, skip_seed_inventory: true)
      sale_order = create(:sale_order, status: 'Preparing', order_date: Date.current)
      create(:sale_order_item,
             sale_order: sale_order,
             product: product,
             quantity: 2,
             unit_cost: 5,
             unit_final_price: 100,
             total_line_cost: 200)
      create(:inventory, product: product, sale_order: sale_order, purchase_cost: 50, status: :sold)
      create(:inventory, product: product, sale_order: sale_order, purchase_cost: 50, status: :sold)

      result = described_class.new(
        start_date: Date.current.beginning_of_year,
        end_date: Date.current.end_of_day,
        time_reference: Time.zone.now
      ).call

      product_row = result[:worst_margin].find { |row| row[:id] == product.id } ||
                    result[:worst_score].find { |row| row[:id] == product.id }

      expect(product_row).to be_present
      expect(product_row[:revenue]).to eq(200.to_d)
      expect(product_row[:cogs]).to eq(100.to_d)
      expect(product_row[:margin_pct]).to eq(50.0)
    end
  end
end
