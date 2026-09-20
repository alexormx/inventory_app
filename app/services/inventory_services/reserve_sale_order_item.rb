# frozen_string_literal: true

module InventoryServices
  class ReserveSaleOrderItem
    class InsufficientInventory < StandardError; end

    Result = Struct.new(
      :assigned,
      :released,
      :total_assigned,
      :missing,
      :inventories,
      :assigned_inventories,
      keyword_init: true
    )

    # held_inventory_ids: exact physical units the CALLER already owns through
    # an active CartInventoryHold. They are consumed first and are the only
    # active holds this call may touch; every other cart's hold is invisible.
    # Allocators that own nothing (PreorderAllocator, admin paths) pass none
    # and therefore see no held unit at all.
    def self.call(sale_order_item, strict: true, dry_run: false, held_inventory_ids: [])
      new(sale_order_item, strict: strict, dry_run: dry_run,
                           held_inventory_ids: held_inventory_ids).call
    end

    def initialize(sale_order_item, strict:, dry_run:, held_inventory_ids: [])
      @sale_order_item = sale_order_item
      @strict = strict
      @dry_run = dry_run
      @held_inventory_ids = Array(held_inventory_ids).compact.uniq
    end

    def call
      result = nil

      ActiveRecord::Base.transaction do
        line = SaleOrderItem.lock.find(@sale_order_item.id)
        existing = Inventory.where(sale_order_item_id: line.id).lock.order(:id).to_a
        desired = line.immediate_quantity
        released = release_excess!(existing, desired)
        retained = existing.first(desired)
        needed = [desired - retained.size, 0].max
        candidates = locked_candidates(line, needed)

        if @strict && candidates.size < needed
          raise InsufficientInventory,
                "#{line.product.product_name} ya no tiene inventario suficiente para completar la compra."
        end

        reserve!(line, candidates) unless @dry_run
        all_assigned = retained + candidates
        result = Result.new(
          assigned: candidates.size,
          released: released,
          total_assigned: all_assigned.size,
          missing: [desired - all_assigned.size, 0].max,
          inventories: all_assigned,
          assigned_inventories: candidates
        )

        raise ActiveRecord::Rollback if @dry_run
      end

      result
    end

    private

    def locked_candidates(line, needed)
      return [] if needed.zero?

      # The caller's own held units come first and exactly: checkout must
      # consume the rows it reserved for this cart, never swap them for
      # equivalent ones while leaving the held rows claimed.
      held = locked_held_rows(line, needed)
      remaining = needed - held.size
      return held if remaining <= 0

      held + locked_free_rows(line, remaining, exclude: held.map(&:id))
    end

    # Re-validated under FOR UPDATE rather than trusted from the request that
    # computed them: right product, right condition, still sellable, and the
    # hold still active at database time. An expired hold yields nothing here,
    # so checkout can never resurrect one.
    def locked_held_rows(line, needed)
      return [] if @held_inventory_ids.empty?

      Inventory.customer_sellable
               .where(product_id: line.product_id, item_condition: line.item_condition)
               .where(id: CartInventoryHold.active
                                           .where(inventory_id: @held_inventory_ids)
                                           .select(:inventory_id))
               .order(:id)
               .lock
               .limit(needed)
               .to_a
    end

    def locked_free_rows(line, needed, exclude: [])
      available_status = Inventory.statuses.fetch('available')
      scope = Inventory.customer_sellable
                       .where(product_id: line.product_id, item_condition: line.item_condition)
      scope = scope.where.not(id: exclude) if exclude.any?
      # Units held by anyone else are not free stock. Rows this caller owns are
      # already in `held`, so excluding the rest is correct here.
      scope.where.not(id: CartInventoryHold.active
                                           .where.not(inventory_id: @held_inventory_ids)
                                           .select(:inventory_id))
           .order(
             Arel.sql("CASE WHEN status = #{available_status} THEN 0 ELSE 1 END"),
             :created_at,
             :id
           )
           .lock
           .limit(needed)
           .to_a
    end

    def reserve!(line, inventories)
      price = line.unit_final_price || line.unit_selling_price
      raise ArgumentError, 'La línea no tiene precio final.' if price.nil?

      product = line.product
      inventories.each do |inventory|
        inventory.stock_update_product = product
        inventory.update!(
          status: inventory.in_transit? ? :pre_reserved : :reserved,
          sale_order_id: line.sale_order_id,
          sale_order_item_id: line.id,
          sold_price: price.to_d,
          status_changed_at: Time.current
        )
      end
    end

    def release_excess!(existing, desired)
      excess = existing.size - desired
      return 0 unless excess.positive?

      releasable = existing.reverse.select { |inventory| inventory.reserved? || inventory.pre_reserved? }
      raise InsufficientInventory, 'No se puede liberar inventario que ya fue vendido.' if releasable.size < excess

      return excess if @dry_run

      releasable.first(excess).each do |inventory|
        inventory.update!(
          status: inventory.pre_reserved? ? :in_transit : :available,
          sale_order_id: nil,
          sale_order_item_id: nil,
          sold_price: nil,
          status_changed_at: Time.current
        )
      end
      excess
    end
  end
end
