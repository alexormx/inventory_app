# frozen_string_literal: true

class ProductDescriptionDraft < ApplicationRecord
  belongs_to :product
  belongs_to :published_by, class_name: "User", optional: true

  enum :status, {
    queued:          "queued",
    generating:      "generating",
    draft_generated: "draft_generated",
    published:       "published",
    rejected:        "rejected",
    failed:          "failed"
  }, default: :queued

  validates :status, presence: true
  validates :product_id, presence: true
  validates :confidence_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true

  scope :latest_for_product, ->(product_id) { where(product_id: product_id).order(created_at: :desc) }
  scope :reviewable, -> { where(status: :draft_generated) }
  scope :recent, -> { order(created_at: :desc) }

  before_create :snapshot_original_data

  def publishable?
    draft_generated? && draft_content.present?
  end

  def total_tokens
    (tokens_input || 0) + (tokens_output || 0)
  end

  def estimated_cost_usd
    return nil unless estimated_cost_cents
    estimated_cost_cents / 100.0
  end

  private

  def snapshot_original_data
    return unless product

    self.original_description = product.description if original_description.nil?
    self.original_attributes  = product.parsed_custom_attributes if original_attributes.blank?
  end
end
