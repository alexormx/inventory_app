require 'rails_helper'

RSpec.describe User, type: :model do
  describe "Validations" do
    before do
      User.create!(name: "Test User", email: "test@example.com", password: "password", role: "customer", contact_name: "Test Contact", phone: "+123456789", address: "Test Address")
    end
    it { should validate_presence_of(:role) }
    it { should validate_inclusion_of(:role).in_array(%w[customer supplier admin]) }
    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_presence_of(:email) }
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should allow_value("user@example.com").for(:email) }
    it { should validate_presence_of(:contact_name) }
    it { should validate_length_of(:contact_name).is_at_most(100) }
    it { should validate_presence_of(:phone) }
    it { should allow_value("+123456789").for(:phone) }
    it { should validate_presence_of(:address) }
    it { should validate_numericality_of(:discount_rate).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100).allow_nil }
  end

  describe "Associations" do
    it { should have_many(:purchase_orders).dependent(:restrict_with_error) }
    it { should have_many(:sale_orders).dependent(:restrict_with_error) }
  end
end