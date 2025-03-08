require 'rails_helper'

RSpec.describe User, type: :model do
  describe "Validations" do
    before do
      User.create!(name: "Test User", email: "test@example.com", password: "password", role: "customer", phone: "1234567890", address: "Test Address")
    end

    # ✅ Email validations
    it { should validate_presence_of(:email)}
    it { should validate_uniqueness_of(:email).case_insensitive }
    it { should allow_value("user@example.com").for(:email) }

    # ✅ Password validations
    it { should validate_presence_of(:password) }
    it { should validate_length_of(:password).is_at_least(6) }

    # ✅ Role validations
    it { should validate_presence_of(:role) }
    it { should validate_inclusion_of(:role).in_array(%w[customer supplier admin]) }

    # ✅ Name validations
    it { should allow_value(nil).for(:name) }
    it { should validate_length_of(:name).is_at_most(255) }

    # ✅ Address validations
    it { should allow_value(nil).for(:address) }

    # ✅ Phone validations
    it { should allow_value(nil).for(:phone) }
    it { should allow_value("1234567890").for(:phone) }
    it { should_not allow_value("+1234567890").for(:phone) }
    it { should_not allow_value("1234567").for(:phone) }

    # ✅ Discount rate validations
    it { should allow_value(nil).for(:discount_rate) }
    it { should validate_numericality_of(:discount_rate).is_greater_than_or_equal_to(0) }

  end

  describe "Associations" do
    it { should have_many(:purchase_orders).dependent(:restrict_with_error) }
    it { should have_many(:sale_orders).dependent(:restrict_with_error) }
  end
end