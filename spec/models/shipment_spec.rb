require 'rails_helper'

RSpec.describe Shipment, type: :model do
  describe "Validations" do
    it { should validate_presence_of(:carrier) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:tracking_number) }
  end

  describe "Associations" do
    it { should belong_to(:sale_order).with_foreign_key("sale_order_id") }
  end
end