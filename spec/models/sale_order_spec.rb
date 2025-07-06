require 'rails_helper'

RSpec.describe SaleOrder, type: :model do
  describe "Validations" do
    it { should validate_presence_of(:order_date) }
    it { should validate_presence_of(:total_order_value) }
  end

  describe "Associations" do
    it { should belong_to(:user) }
    it { should have_many(:inventory).with_foreign_key("sale_order_id") }
    it { should have_many(:payments) }
    it { should have_one(:shipment).with_foreign_key("sale_order_id") }
  end
end