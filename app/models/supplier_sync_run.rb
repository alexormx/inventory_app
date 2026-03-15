# frozen_string_literal: true

class SupplierSyncRun < ApplicationRecord
  belongs_to :supplier_catalog_item, optional: true

  attribute :metadata, :json, default: -> { {} }
  attribute :error_samples, :json, default: -> { [] }

  validates :source, :mode, :status, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :completed, -> { where(status: "completed") }

  def start!
    update!(status: "running", started_at: Time.current)
  end

  def complete!(extra_attrs = {})
    update!({ status: "completed", finished_at: Time.current }.merge(extra_attrs))
  end

  def fail!(message, extra_attrs = {})
    samples = Array(error_samples)
    samples << message if message.present?

    update!({
      status: "failed",
      finished_at: Time.current,
      error_count: error_count.to_i + 1,
      error_samples: samples.last(10)
    }.merge(extra_attrs))
  end
end