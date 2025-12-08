require 'rails_helper'

RSpec.describe Shipment, type: :model do
  describe 'Validations' do
    it { should validate_presence_of(:carrier) }
    it { should validate_presence_of(:tracking_number) }
    it { should define_enum_for(:status).with_values(%i[pending shipped delivered canceled returned]) }
  end

  describe 'Associations' do
    it { should belong_to(:sale_order) }
  end

  describe "custom date validation" do
    it "is invalid when actual_delivery is before estimated_delivery" do
      estimated = Date.current
      actual    = estimated - 1.day
      shipment = build(:shipment, estimated_delivery: estimated, actual_delivery: actual)

      expect(shipment).to be_invalid
      expect(shipment.errors[:actual_delivery].join).to match(/no puede ser anterior/i)
    end
  end
end
