# frozen_string_literal: true

class SupplierCatalogReview < ApplicationRecord
  REVIEW_MODES = %w[recent_additions recent_arrivals].freeze

  belongs_to :supplier_catalog_item
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :reviewed_at, presence: true
  validates :review_mode, presence: true, inclusion: { in: REVIEW_MODES }
end