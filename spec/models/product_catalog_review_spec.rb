# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProductCatalogReview, type: :model do
  subject { build(:product_catalog_review) }

  describe "associations" do
    it { is_expected.to belong_to(:product) }
    it { is_expected.to belong_to(:reviewed_by).class_name("User").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:reviewed_at) }

    it "validates uniqueness of product_id" do
      create(:product_catalog_review)
      duplicate = build(:product_catalog_review, product: ProductCatalogReview.last.product)
      expect(duplicate).not_to be_valid
    end
  end

  describe "factory" do
    it "creates a valid record" do
      review = create(:product_catalog_review)
      expect(review).to be_persisted
    end
  end
end
