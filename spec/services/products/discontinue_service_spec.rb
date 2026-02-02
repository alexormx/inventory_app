# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Products::DiscontinueService, type: :service do
  let(:product) { create(:product, skip_seed_inventory: true, discontinued: false) }
  let(:service) { described_class.new(product) }

  describe '#discontinue!' do
    context 'when product has brand_new inventory' do
      before do
        create_list(:inventory, 3, product: product, item_condition: :brand_new, status: :available)
        create(:inventory, product: product, item_condition: :brand_new, status: :sold) # should not be converted
      end

      it 'converts all available brand_new inventory to misb' do
        result = service.discontinue!(misb_price: 150.0)

        expect(result[:converted_count]).to eq(3)
        expect(product.inventories.misb.count).to eq(3)
        expect(product.inventories.brand_new.available.count).to eq(0)
      end

      it 'sets the selling_price on converted inventory' do
        service.discontinue!(misb_price: 150.0)

        product.inventories.misb.each do |inv|
          expect(inv.selling_price).to eq(150.0)
        end
      end

      it 'marks product as discontinued' do
        service.discontinue!(misb_price: 150.0)

        expect(product.reload.discontinued?).to be true
      end

      it 'does not convert sold inventory' do
        service.discontinue!(misb_price: 150.0)

        expect(product.inventories.brand_new.sold.count).to eq(1)
      end
    end

    context 'when product is already discontinued' do
      before { product.update!(discontinued: true) }

      it 'raises an error' do
        expect { service.discontinue!(misb_price: 150.0) }.to raise_error(ArgumentError, /ya está descontinuado/)
      end
    end

    context 'when price is invalid' do
      it 'raises an error for zero price' do
        expect { service.discontinue!(misb_price: 0) }.to raise_error(ArgumentError, /precio válido/)
      end

      it 'raises an error for negative price' do
        expect { service.discontinue!(misb_price: -10) }.to raise_error(ArgumentError, /precio válido/)
      end
    end
  end

  describe '#reverse!' do
    let(:product) { create(:product, skip_seed_inventory: true, discontinued: true) }

    context 'when product has misb inventory' do
      before do
        create_list(:inventory, 2, product: product, item_condition: :misb, status: :available, selling_price: 150.0)
      end

      it 'converts misb inventory back to brand_new' do
        result = service.reverse!

        expect(result[:converted_count]).to eq(2)
        expect(product.inventories.brand_new.count).to eq(2)
        expect(product.inventories.misb.count).to eq(0)
      end

      it 'unmarks product as discontinued' do
        service.reverse!

        expect(product.reload.discontinued?).to be false
      end

      it 'clears selling_price when no new_price specified' do
        service.reverse!

        product.inventories.brand_new.each do |inv|
          expect(inv.selling_price).to be_nil
        end
      end

      it 'sets selling_price when new_price specified' do
        service.reverse!(new_price: 100.0)

        product.inventories.brand_new.each do |inv|
          expect(inv.selling_price).to eq(100.0)
        end
      end
    end

    context 'when product is not discontinued' do
      let(:product) { create(:product, skip_seed_inventory: true, discontinued: false) }

      it 'raises an error' do
        expect { service.reverse! }.to raise_error(ArgumentError, /no está descontinuado/)
      end
    end
  end
end
