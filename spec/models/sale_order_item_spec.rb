require 'rails_helper'

RSpec.describe SaleOrderItem, type: :model do
  describe 'associations' do
    it { should belong_to(:sale_order) }
    it { should belong_to(:product) }
  end

  describe 'validations' do
    it { should validate_presence_of(:quantity) }
    it { should validate_numericality_of(:quantity).is_greater_than(0) }
    it { should validate_presence_of(:unit_cost) }
    it { should validate_numericality_of(:unit_cost).is_greater_than_or_equal_to(0) }
  end
end
