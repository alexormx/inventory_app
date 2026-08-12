# frozen_string_literal: true

class InventoryEvent < ApplicationRecord
  belongs_to :inventory
  belongs_to :product

  EVENT_TYPES = %w[
    purchase_cost_recalculated
    sale_order_link_cleared
    sale_order_item_destroy_release
    distributed_cost_applied
    status_change
    reconciliation_orphan_destroyed
    reconciliation_missing_created
    product_dimensions_changed
    physical_inventory_verification
  ].freeze

  PHYSICAL_VERIFICATION_RESULTS = %w[found damaged missing].freeze
  PHYSICAL_VERIFICATION_METADATA_KEYS = %w[
    result
    notes
    actor_id
    actor_email
    actor_name
    previous_status
    new_status
    previous_location_id
    new_location_id
    product_id
    purchase_order_id
    purchase_order_item_id
    sale_order_id
    sale_order_item_id
    expected_updated_at
    verified_inventory_updated_at
  ].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
  validate :physical_verification_metadata_is_complete, if: :physical_inventory_verification?

  private

  def physical_inventory_verification?
    event_type == 'physical_inventory_verification'
  end

  def physical_verification_metadata_is_complete
    data = metadata.is_a?(Hash) ? metadata.stringify_keys : {}
    missing_keys = PHYSICAL_VERIFICATION_METADATA_KEYS.reject { |key| data.key?(key) }

    errors.add(:metadata, "must include #{missing_keys.join(', ')}") if missing_keys.any?
    errors.add(:metadata, 'has an invalid verification result') unless PHYSICAL_VERIFICATION_RESULTS.include?(data['result'])
    errors.add(:metadata, 'must identify the actor') if data['actor_id'].blank?
  end
end
