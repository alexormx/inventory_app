# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Dashboard::GeoSalesBuilder do
  describe '#call' do
    it 'uses line-item revenue and includes preparing orders in geography totals' do
      user = create(:user, address: 'Guadalajara, Jalisco, Mexico')
      product = create(:product, skip_seed_inventory: true)
      sale_order = create(:sale_order,
                          user: user,
                          status: 'Preparing',
                          order_date: Date.current,
                          total_order_value: 999,
                          subtotal: 999,
                          total_tax: 0,
                          tax_rate: 0)
      create(:sale_order_item,
             sale_order: sale_order,
             product: product,
             quantity: 2,
             unit_final_price: 100,
             unit_cost: 10,
             total_line_cost: 200)

      result = described_class.new(time_reference: Time.zone.now).call
      mexico_row = result[:ytd][:countries].find { |row| row[:name] == 'Mexico' }
      jalisco_row = result[:ytd][:mexico_states].find { |row| row[:state] == 'Jalisco' }

      expect(mexico_row).to be_present
      expect(mexico_row[:orders]).to eq(1)
      expect(mexico_row[:revenue]).to eq(200.to_d)

      expect(jalisco_row).to be_present
      expect(jalisco_row[:revenue]).to eq(200.to_d)
    end
  end
end
