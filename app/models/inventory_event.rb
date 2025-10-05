class InventoryEvent < ApplicationRecord
  belongs_to :inventory
  belongs_to :product

  EVENT_TYPES = %w[
    purchase_cost_recalculated
    sale_order_link_cleared
    sale_order_item_destroy_release
    distributed_cost_applied
    status_change
  ].freeze

  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }
end
