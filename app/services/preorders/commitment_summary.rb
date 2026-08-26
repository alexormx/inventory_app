# frozen_string_literal: true

module Preorders
  # Read-only, source-of-truth operational view for one product. No cached
  # counters: every value is derived from Inventory and PreorderReservation.
  class CommitmentSummary
    Result = Data.define(
      :in_transit_total,
      :inbound_committed,
      :inbound_free,
      :pending_preorder,
      :received_unlocated_reserved,
      :received_unlocated_free,
      :located_reserved,
      :physical_free_on_hand,
      :true_free_sellable,
      :unbacked_demand
    )

    def initialize(product)
      @product_id = product&.id
    end

    def call
      inventories = Inventory.where(product_id: @product_id)
      inbound_committed = inventories.where(status: :pre_reserved).count
      inbound_free = inventories.where(status: :in_transit, sale_order_id: nil).count
      pending_preorder = PreorderReservation.pending.where(product_id: @product_id).sum(:quantity).to_i

      Result.new(
        in_transit_total: inbound_committed + inbound_free,
        inbound_committed: inbound_committed,
        inbound_free: inbound_free,
        pending_preorder: pending_preorder,
        received_unlocated_reserved: inventories.where(status: :reserved, inventory_location_id: nil).count,
        received_unlocated_free: inventories.where(
          status: :available, inventory_location_id: nil, sale_order_id: nil
        ).count,
        located_reserved: inventories.where(status: :reserved).where.not(inventory_location_id: nil).count,
        physical_free_on_hand: Inventory.customer_on_hand.where(product_id: @product_id).count,
        true_free_sellable: Inventory.customer_sellable.where(product_id: @product_id).count,
        unbacked_demand: pending_preorder
      )
    end
  end
end
