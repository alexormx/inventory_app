# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationHelper, type: :helper do
  let(:product) { create(:product) }

  describe '#bootstrap_class_for' do
    it 'returns success class for notice' do
      expect(helper.bootstrap_class_for(:notice)).to eq('alert-success')
    end

    it 'returns info class for unknown key' do
      expect(helper.bootstrap_class_for(:other)).to eq('alert-info')
    end
  end

  describe '#currency_symbol_for' do
    it 'returns symbol when known' do
      expect(helper.currency_symbol_for('MXN')).to eq('$')
    end

    it 'returns code when unknown' do
      expect(helper.currency_symbol_for('XYZ')).to eq('XYZ')
    end
  end

  describe '#cart_item_count' do
    it 'counts only products that still exist in the cart contract' do
      session[:cart] = { product.id.to_s => { 'brand_new' => 1 }, '999999999' => { 'brand_new' => 3 } }

      expect(helper.cart_item_count).to eq(1)
    end
  end
end
