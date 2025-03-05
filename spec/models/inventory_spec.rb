require 'rails_helper'

RSpec.describe Inventory, type: :model do
  describe "Validations" do
    it { should validate_presence_of(:purchase_cost) }
    it { should validate_presence_of(:status) }
  end

  describe "Associations" do
    it { should belong_to(:purchase_order).optional }
    it { should belong_to(:sale_order).optional }
    it { should belong_to(:product).with_foreign_key("product_id") }
  end
end