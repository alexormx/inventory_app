require 'rails_helper'

RSpec.describe CanceledOrderItem, type: :model do
  describe "Validations" do
    it { should validate_presence_of(:canceled_quantity) }
    it { should validate_presence_of(:sale_price_at_cancellation) }
  end

  describe "Associations" do
    it { should belong_to(:sale_order) }
    it { should belong_to(:product) }
  end
end