# frozen_string_literal: true

module InventoryServices
  # Calcula desglose de disponibilidad inmediata vs pendiente.
  # Orden de consumo: on_hand (available) -> in_transit -> preorder/backorder.
  # Retorna struct con: requested, on_hand, in_transit, immediate, in_transit_qty, pending, pending_type
  class AvailabilitySplitter
    Result = Struct.new(
      :requested, :on_hand, :in_transit, :immediate, :in_transit_qty,
      :pending, :pending_type,
      keyword_init: true
    )

    def initialize(product, requested_qty)
      @product = product
      @requested = requested_qty.to_i
    end

    def call
      return empty if @requested <= 0 || @product.nil?

      on_hand = @product.respond_to?(:current_on_hand) ? @product.current_on_hand.to_i : 0
      in_transit = @product.respond_to?(:in_transit_count) ? @product.in_transit_count.to_i : 0

      immediate = [@requested, on_hand].min
      remaining = @requested - immediate

      in_transit_qty = [remaining, in_transit].min
      remaining -= in_transit_qty

      pending = remaining
      pending_type = nil
      if pending.positive?
        if @product.respond_to?(:preorder_available) && @product.preorder_available
          pending_type = :preorder
        elsif @product.respond_to?(:backorder_allowed) && @product.backorder_allowed
          pending_type = :backorder
        end
      end

      Result.new(
        requested: @requested,
        on_hand: on_hand,
        in_transit: in_transit,
        immediate: immediate,
        in_transit_qty: in_transit_qty,
        pending: pending,
        pending_type: pending_type
      )
    end

    private

    def empty
      Result.new(
        requested: @requested, on_hand: 0, in_transit: 0,
        immediate: 0, in_transit_qty: 0,
        pending: 0, pending_type: nil
      )
    end
  end
end
