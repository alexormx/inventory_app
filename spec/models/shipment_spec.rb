require 'rails_helper'

RSpec.describe Shipment, type: :model do
  describe 'Validations' do
    it { should validate_presence_of(:carrier) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:tracking_number) }
  end

  describe 'Associations' do
    it { should belong_to(:sale_order).with_foreign_key('sale_order_id') }
  end

  describe 'custom date validation' do
    it 'is invalid when actual_delivery is before estimated_delivery' do
      shipment = Shipment.new(tracking_number: '123', carrier: 'UPS', sale_order: build(:sale_order), estimated_delivery: Date.today, actual_delivery: Date.yesterday)
      expect(shipment).to be_invalid
      expect(shipment.errors[:actual_delivery]).to be_present
    end
  end
end
