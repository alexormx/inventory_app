require 'rails_helper'

RSpec.describe PurchaseOrderItem, type: :model do
  describe "associations" do
    it { should belong_to(:purchase_order) }
    it { should belong_to(:product) }
  end

  describe "validations" do
    it { should validate_presence_of(:quantity) }
    it { should validate_numericality_of(:quantity).is_greater_than(0) }
  end

  describe "#calculated_fields" do
    let(:item) { build(:purchase_order_item, quantity: 5, unit_cost: 100.0, unit_additional_cost: 20.0) }

    it "calculates unit_compose_cost" do
      expect(item.unit_compose_cost).to eq(120.0)
    end

    it "calculates total_line_cost" do
      expect(item.total_line_cost).to eq(600.0)
    end
  end
end
