# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Dashboard Rankings', type: :request do
  describe 'GET rankings endpoints' do
    let(:admin) { create(:user, :admin) }

    before do
      sign_in admin
    end

    it 'shows top categories using paid-status sales only' do
      paid_category = "Paid Cat #{SecureRandom.hex(3)}"
      pending_category = "Pending Cat #{SecureRandom.hex(3)}"

      paid_product = create(:product, category: paid_category, skip_seed_inventory: true)
      pending_product = create(:product, category: pending_category, skip_seed_inventory: true)

      paid_order = create(:sale_order, status: 'Preparing', order_date: Date.current)
      pending_order = create(:sale_order, status: 'Pending', order_date: Date.current)

      create(:sale_order_item,
             sale_order: paid_order,
             product: paid_product,
             quantity: 1,
             unit_final_price: 100,
             unit_cost: 10,
             total_line_cost: 100)
      create(:sale_order_item,
             sale_order: pending_order,
             product: pending_product,
             quantity: 1,
             unit_final_price: 500,
             unit_cost: 10,
             total_line_cost: 500)

      get admin_dashboard_categories_rank_path, params: { period: 'ytd', metric: 'rev' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(paid_category)
      expect(response.body).not_to include(pending_category)
    end

    it 'shows top customers using paid-status sales only' do
      paid_customer_name = "Paid Customer #{SecureRandom.hex(3)}"
      pending_customer_name = "Pending Customer #{SecureRandom.hex(3)}"

      paid_customer = create(:user, name: paid_customer_name)
      pending_customer = create(:user, name: pending_customer_name)
      product = create(:product, skip_seed_inventory: true)

      paid_order = create(:sale_order, user: paid_customer, status: 'Preparing', order_date: Date.current)
      pending_order = create(:sale_order, user: pending_customer, status: 'Pending', order_date: Date.current)

      create(:sale_order_item,
             sale_order: paid_order,
             product: product,
             quantity: 1,
             unit_final_price: 120,
             unit_cost: 10,
             total_line_cost: 120)
      create(:sale_order_item,
             sale_order: pending_order,
             product: product,
             quantity: 1,
             unit_final_price: 700,
             unit_cost: 10,
             total_line_cost: 700)

      get admin_dashboard_customers_rank_path, params: { period: 'ytd', metric: 'sales' }

      expect(response).to have_http_status(:success)
      expect(response.body).to include(paid_customer_name)
      expect(response.body).not_to include(pending_customer_name)
    end
  end
end
