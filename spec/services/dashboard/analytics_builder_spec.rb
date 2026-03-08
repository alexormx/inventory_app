# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dashboard::AnalyticsBuilder do
  describe '#category_charts_bundle' do
    it 'builds category and brand charts using paid-status sales only' do
      target_year = 2200 + SecureRandom.random_number(200)
      range_start = Date.new(target_year, 1, 1)
      range_end = Time.zone.local(target_year, 5, 15, 23, 59, 59)
      order_date = Date.new(target_year, 5, 15)
      paid_category = "Model Kits #{SecureRandom.hex(3)}"
      pending_category = "Pending Category #{SecureRandom.hex(3)}"
      paid_brand = "Bandai #{SecureRandom.hex(3)}"
      pending_brand = "Other Brand #{SecureRandom.hex(3)}"

      paid_product = create(:product, category: paid_category, brand: paid_brand, average_purchase_cost: 40, skip_seed_inventory: true)
      pending_product = create(:product, category: pending_category, brand: pending_brand, average_purchase_cost: 30, skip_seed_inventory: true)

      paid_order = create(:sale_order, status: 'Preparing', order_date: order_date)
      pending_order = create(:sale_order, status: 'Pending', order_date: order_date)

      create(:sale_order_item, sale_order: paid_order, product: paid_product, quantity: 2, unit_final_price: 100, unit_cost: 10, total_line_cost: 200)
      create(:sale_order_item, sale_order: pending_order, product: pending_product, quantity: 1, unit_final_price: 500, unit_cost: 10, total_line_cost: 500)
      paid_product.update_column(:average_purchase_cost, 40)

      so_ytd = SaleOrder.where.not(status: 'Canceled').where(order_date: range_start..range_end)
        result = described_class.new(
          so_ytd: so_ytd,
          start_date: range_start,
          end_date: range_end
        ).category_charts_bundle

      expect(result[:monthly_by_category][:series].map { |row| row[:name] }).to include(paid_category)
      expect(result[:monthly_by_category][:series].map { |row| row[:name] }).not_to include(pending_category)
      expect(result[:monthly_by_category][:series].sum { |row| row[:data].sum(&:to_d) }).to eq(200.to_d)
      expect(result[:brand_profit][:brands]).to include(paid_brand)
      expect(result[:brand_profit][:brands]).not_to include(pending_brand)
      expect(result[:category_profit][:profit]).to include(120.to_d)
    end
  end
end
