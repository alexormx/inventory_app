# frozen_string_literal: true

class ProductCatalogReview < ApplicationRecord
  belongs_to :product
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :product_id, uniqueness: true
  validates :reviewed_at, presence: true
end
