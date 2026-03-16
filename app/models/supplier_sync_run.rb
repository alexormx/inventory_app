# frozen_string_literal: true

class SupplierSyncRun < ApplicationRecord
  belongs_to :supplier_catalog_item, optional: true

  attribute :metadata, :json, default: -> { {} }
  attribute :error_samples, :json, default: -> { [] }

  validates :source, :mode, :status, presence: true

  STALE_THRESHOLD = 30.minutes

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[queued running]) }
  scope :genuinely_active, -> { active.where("updated_at > ?", STALE_THRESHOLD.ago) }
  scope :completed, -> { where(status: "completed") }
  scope :running, -> { where(status: "running") }
  scope :stale, -> { active.where("updated_at <= ?", STALE_THRESHOLD.ago) }

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

  def request_stop!
    update!(metadata: merged_metadata(
      "stop_requested" => true,
      "stop_requested_at" => Time.current.iso8601
    ))
  end

  def progress_percent
    total_items = metadata_value("progress_total_items").to_i
    return item_progress_percent(total_items) if total_items.positive?

    total_pages = metadata_value("progress_total_pages").to_i
    return page_progress_percent(total_pages) if total_pages.positive?

    status == "completed" ? 100 : 0
  end

  def progress_label
    processed = processed_count.to_i
    total_items = metadata_value("progress_total_items")

    if total_items.present?
      "#{processed} de #{total_items} productos procesados"
    else
      current_page = metadata_value("progress_current_page")
      total_pages = metadata_value("progress_total_pages")
      if current_page.present? && total_pages.present?
        "Página #{current_page} de #{total_pages} · #{processed} productos procesados"
      else
        "#{processed} productos procesados"
      end
    end
  end

  def progress_description
    parts = []
    parts << progress_label
    parts << "creados #{created_count}"
    parts << "actualizados #{updated_count}"
    parts << "omitidos #{skipped_count}" if skipped_count.to_i.positive?
    parts << "errores #{error_count}" if error_count.to_i.positive?
    parts.join(" · ")
  end

  def progress_state_class
    case status
    when "completed" then "bg-success"
    when "failed", "cancelled" then "bg-danger"
    else "bg-primary progress-bar-striped progress-bar-animated"
    end
  end

  def update_progress!(counts: {}, metadata: {})
    attrs = counts.compact.transform_values { |value| value.to_i }
    attrs[:metadata] = merged_metadata(metadata) if metadata.present?
    update!(attrs)
  end

  def stop_requested?
    metadata.is_a?(Hash) && metadata["stop_requested"] == true
  end

  def cancel!(extra_attrs = {})
    update!({ status: "cancelled", finished_at: Time.current }.merge(extra_attrs))
  end

  def stale?
    %w[queued running].include?(status) && updated_at <= STALE_THRESHOLD.ago
  end

  def self.cancel_stale!
    stale.find_each { |run| run.cancel!(metadata: run.send(:merged_metadata, "auto_cancelled" => "stale")) }
  end

  private

  def metadata_value(key)
    metadata.is_a?(Hash) ? metadata[key] : nil
  end

  def item_progress_percent(total_items)
    value = (processed_count.to_f / total_items) * 100
    [[value.round, 1].max, 100].min
  end

  def page_progress_percent(total_pages)
    current_page = metadata_value("progress_current_page").to_i
    page_item_count = metadata_value("progress_page_item_count").to_i
    page_item_index = metadata_value("progress_page_item_index").to_i

    completed_pages = [current_page - 1, 0].max
    page_fraction = page_item_count.positive? ? (page_item_index.to_f / page_item_count) : 0.0
    value = ((completed_pages + page_fraction) / total_pages) * 100
    [[value.round, 1].max, 100].min
  end

  def merged_metadata(new_values)
    current = metadata.is_a?(Hash) ? metadata.deep_dup : {}
    current.merge(new_values)
  end
end