# frozen_string_literal: true

class SupplierCatalogSource < ApplicationRecord
  belongs_to :supplier_catalog_item

  attribute :image_urls, :json, default: -> { [] }
  attribute :normalized_payload, :json, default: -> { {} }
  attribute :raw_payload, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }

  validates :source, presence: true, uniqueness: { scope: :supplier_catalog_item_id }
  validates :fetch_status, presence: true

  scope :available, -> { where(fetch_status: "ok") }
  scope :recently_seen, -> { where.not(last_seen_at: nil).order(last_seen_at: :desc) }
end