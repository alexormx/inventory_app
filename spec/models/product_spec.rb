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

end