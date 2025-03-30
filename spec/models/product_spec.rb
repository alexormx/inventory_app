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
end