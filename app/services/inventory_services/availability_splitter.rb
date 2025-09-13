module InventoryServices
  # Calcula desglose de disponibilidad inmediata vs pendiente (preorder/backorder futuro).
  # Retorna struct con: requested, on_hand, immediate, pending, pending_type
  class AvailabilitySplitter
    Result = Struct.new(:requested, :on_hand, :immediate, :pending, :pending_type, keyword_init: true)

    def initialize(product, requested_qty)
      @product = product
      @requested = requested_qty.to_i
    end

    def call
      return empty if @requested <= 0 || @product.nil?
      on_hand = @product.respond_to?(:current_on_hand) ? @product.current_on_hand.to_i : 0
      immediate = [@requested, on_hand].min
      pending = @requested - immediate
      pending_type = nil
      if pending > 0
        if @product.respond_to?(:preorder_available) && @product.preorder_available
          pending_type = :preorder
        elsif @product.respond_to?(:backorder_allowed) && @product.backorder_allowed
          pending_type = :backorder
        end
      end
      Result.new(requested: @requested, on_hand: on_hand, immediate: immediate, pending: pending, pending_type: pending_type)
    end

    private

    def empty
      Result.new(requested: @requested, on_hand: 0, immediate: 0, pending: 0, pending_type: nil)
    end
  end
end
