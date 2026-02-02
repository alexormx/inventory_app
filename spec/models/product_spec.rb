require 'rails_helper'

RSpec.describe Product, type: :model do
  describe "Validations" do
    it { should validate_presence_of(:product_sku) }
    it { should validate_presence_of(:product_name) }
    it { should validate_presence_of(:selling_price) }
    it { should validate_numericality_of(:selling_price).is_greater_than(0) }
    it { should validate_numericality_of(:maximum_discount).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:minimum_price).is_greater_than_or_equal_to(0) }
  end

  describe 'whatsapp_code' do
    it 'requires uniqueness of whatsapp_code' do
      code = "WGT#{SecureRandom.hex(3).upcase}" # minimize collision risk
      # Create first product directly (skip factory callbacks that may introduce duplicates)
      Product.create!(
        product_sku: "SKU-UNIQ-#{SecureRandom.hex(4)}",
        product_name: 'Uniq Name A',
        brand: 'BrandX',
        category: 'diecast',
        whatsapp_code: code,
        selling_price: 100,
        minimum_price: 50,
        maximum_discount: 0
      )
      dup = Product.new(
        product_sku: "SKU-UNIQ-#{SecureRandom.hex(4)}",
        product_name: 'Uniq Name B',
        brand: 'BrandX',
        category: 'diecast',
        whatsapp_code: code,
        selling_price: 100,
        minimum_price: 50,
        maximum_discount: 0
      )
      expect(dup).not_to be_valid
      expect(dup.errors[:whatsapp_code]).to be_present
    end

    it "auto-generates whatsapp_code when blank" do
      product = Product.new(
        product_sku: "SKU-UNIQ-#{SecureRandom.hex(4)}",
        product_name: 'Name C',
        brand: 'BrandY',
        category: 'diecast',
        whatsapp_code: nil,
        selling_price: 100,
        minimum_price: 50,
        maximum_discount: 0
      )
      expect(product.valid?).to be true
      expect(product.whatsapp_code).to be_present
    end
  end

  describe '#available_by_condition' do
    let(:product) { create(:product, skip_seed_inventory: true, selling_price: 100) }

    context 'when product has no inventory' do
      it 'returns an empty array' do
        expect(product.available_by_condition).to eq([])
      end
    end

    context 'when product has only brand_new inventory' do
      before do
        create_list(:inventory, 3, product: product, status: :available, item_condition: :brand_new)
      end

      it 'returns array with one entry for brand_new' do
        result = product.available_by_condition
        expect(result.size).to eq(1)
        expect(result.first[:condition]).to eq('brand_new')
        expect(result.first[:count]).to eq(3)
        expect(result.first[:price]).to eq(100)
        expect(result.first[:collectible]).to be false
      end
    end

    context 'when product has mixed conditions' do
      before do
        create_list(:inventory, 2, product: product, status: :available, item_condition: :brand_new)
        create_list(:inventory, 1, product: product, status: :available, item_condition: :misb, selling_price: 150)
        create(:inventory, product: product, status: :available, item_condition: :loose, selling_price: 75)
      end

      it 'returns array sorted by condition' do
        result = product.available_by_condition
        expect(result.size).to eq(3)
        expect(result.map { |c| c[:condition] }).to eq(%w[brand_new misb loose])
      end

      it 'marks collectibles correctly' do
        result = product.available_by_condition
        brand_new_entry = result.find { |c| c[:condition] == 'brand_new' }
        misb_entry = result.find { |c| c[:condition] == 'misb' }
        expect(brand_new_entry[:collectible]).to be false
        expect(misb_entry[:collectible]).to be true
      end
    end

    context 'when product has only sold inventory' do
      before do
        create(:inventory, product: product, status: :sold, item_condition: :brand_new)
      end

      it 'returns empty array' do
        expect(product.available_by_condition).to eq([])
      end
    end
  end

  describe '#has_collectibles?' do
    let(:product) { create(:product, skip_seed_inventory: true, selling_price: 100) }

    it 'returns false when no inventory' do
      expect(product.has_collectibles?).to be false
    end

    it 'returns false when only brand_new inventory' do
      create(:inventory, product: product, status: :available, item_condition: :brand_new)
      expect(product.has_collectibles?).to be false
    end

    it 'returns true when has misb inventory' do
      create(:inventory, product: product, status: :available, item_condition: :misb, selling_price: 150)
      expect(product.has_collectibles?).to be true
    end

    it 'returns true when has loose inventory' do
      create(:inventory, product: product, status: :available, item_condition: :loose, selling_price: 80)
      expect(product.has_collectibles?).to be true
    end
  end

  describe '#total_available' do
    let(:product) { create(:product, skip_seed_inventory: true, selling_price: 100) }

    it 'returns 0 when no inventory' do
      expect(product.total_available).to eq(0)
    end

    it 'sums all available conditions' do
      create_list(:inventory, 2, product: product, status: :available, item_condition: :brand_new)
      create(:inventory, product: product, status: :available, item_condition: :misb, selling_price: 150)
      create(:inventory, product: product, status: :sold, item_condition: :brand_new)
      expect(product.total_available).to eq(3)
    end
  end
end