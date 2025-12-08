require 'rails_helper'

RSpec.describe Payment, type: :model do
  describe "Validations" do
    it { should validate_presence_of(:amount) }
    it { should validate_presence_of(:payment_method) }
    it { should validate_presence_of(:status) }
  end

  describe "Associations" do
    it { should belong_to(:sale_order) }
  end
end