# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dashboard::RankingsBuilder do
  describe '#top_categories_bundle' do
    it 'keeps only paid-status sales in category rankings' do
      product_paid = create(:product, category: 'Paid Category', skip_seed_inventory: true)
      product_pending = create(:product, category: 'Pending Category', skip_seed_inventory: true)

      paid_order = create(:sale_order, status: 'Preparing', order_date: Date.current)
      pending_order = create(:sale_order, status: 'Pending', order_date: Date.current)

      create(:sale_order_item, sale_order: paid_order, product: product_paid, quantity: 1, unit_final_price: 100, unit_cost: 10, total_line_cost: 100)
      create(:sale_order_item, sale_order: pending_order, product: product_pending, quantity: 1, unit_final_price: 400, unit_cost: 10, total_line_cost: 400)

      so_scope = SaleOrder.where.not(status: 'Canceled')
      so_ytd = so_scope.where(order_date: Date.current.beginning_of_year..Time.zone.now.end_of_day)

      result = described_class.new(
        now: Time.zone.now,
        so_scope: so_scope,
        so_ytd: so_ytd,
        so_ytd_paid: so_ytd.where(status: Dashboard::Metrics::SALE_STATUSES),
        start_date: Date.current.beginning_of_year,
        end_date: Time.zone.now.end_of_day
      ).top_categories_bundle

      expect(result[:top_categories_ytd].map { |row| row[:category] }).to include('Paid Category')
      expect(result[:top_categories_ytd].map { |row| row[:category] }).not_to include('Pending Category')
    end
  end

  describe '#customers_rows' do
    it 'uses paid-status sales for customer sales ranking and keeps reserved values for combined metric' do
      paid_customer = create(:user, name: 'Paid Customer')
      reserved_customer = create(:user, name: 'Reserved Customer')
      product = create(:product, skip_seed_inventory: true)

      paid_order = create(:sale_order, user: paid_customer, status: 'Delivered', order_date: Date.current)
      reserved_order = create(:sale_order, user: reserved_customer, status: 'Pending', order_date: Date.current)

      create(:sale_order_item, sale_order: paid_order, product: product, quantity: 1, unit_final_price: 150, unit_cost: 10, total_line_cost: 150)
      create(:inventory, product: product, sale_order: reserved_order, purchase_cost: 30, status: :reserved)

      so_scope = SaleOrder.where.not(status: 'Canceled')
      so_ytd = so_scope.where(order_date: Date.current.beginning_of_year..Time.zone.now.end_of_day)
      builder = described_class.new(
        now: Time.zone.now,
        so_scope: so_scope,
        so_ytd: so_ytd,
        so_ytd_paid: so_ytd.where(status: Dashboard::Metrics::SALE_STATUSES),
        start_date: Date.current.beginning_of_year,
        end_date: Time.zone.now.end_of_day
      )

      sales_rows = builder.customers_rows(scope: so_ytd, metric: 'sales')
      combined_rows = builder.customers_rows(scope: so_ytd, metric: 'combined')

      expect(sales_rows.map { |row| row[:name] }).to include('Paid Customer')
      expect(sales_rows.map { |row| row[:name] }).not_to include('Reserved Customer')

      reserved_combined = combined_rows.find { |row| row[:name] == 'Reserved Customer' }
      expect(reserved_combined).to be_present
      expect(reserved_combined[:reserved_value]).to eq(30.to_d)
    end
  end
end
