# frozen_string_literal: true

class SupplierCatalogItem < ApplicationRecord
  belongs_to :product, optional: true
  has_many :supplier_catalog_sources, dependent: :destroy
  has_many :supplier_sync_runs, dependent: :nullify
  has_many :supplier_catalog_reviews, dependent: :destroy

  attribute :image_urls, :json, default: -> { [] }
  attribute :details_payload, :json, default: -> { {} }
  attribute :raw_payload, :json, default: -> { {} }

  validates :source_key, presence: true
  validates :external_sku, presence: true, uniqueness: { scope: :source_key }
  validates :canonical_name, presence: true

  scope :linked, -> { where.not(product_id: nil) }
  scope :unlinked, -> { where(product_id: nil) }
  scope :future_release, -> { where(canonical_status: "future_release") }
  scope :recently_seen, -> { where.not(last_seen_at: nil).order(last_seen_at: :desc) }
  scope :recent_hlj_additions, ->(days = 10) { where("last_hlj_recent_added_at >= ?", days.days.ago) }
  scope :recent_hlj_arrivals, ->(days = 10) { where("last_hlj_recent_arrival_at >= ?", days.days.ago) }

  def linked?
    product.present? || product_id.present?
  end

  def future_release?
    canonical_status == "future_release"
  end

  def source_for(source)
    supplier_catalog_sources.find_by(source: source.to_s)
  end

  def review_timestamp_for(feed)
    case feed.to_s
    when "recent_additions"
      last_hlj_recent_added_at
    when "recent_arrivals"
      last_hlj_recent_arrival_at
    end
  end

  def reviewed_for?(feed)
    supplier_catalog_reviews.any? { |review| review.review_mode == feed.to_s }
  end
end