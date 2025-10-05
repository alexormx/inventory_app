# frozen_string_literal: true
module InventoryReconciliation
  class ReconcilePurchaseOrderLinksService
    Result = Struct.new(:destroyed_orphans, :created_missing, :errors, keyword_init: true)

    def initialize(dry_run: false, limit: 10_000, logger: Rails.logger)
      @dry_run = dry_run
      @limit = limit
      @logger = logger
    end

    def call
      destroyed_orphans = 0
      created_missing = 0
      errors = []

      ActiveRecord::Base.transaction do
        destroyed_orphans += destroy_orphans
        created_missing  += create_missing
        raise ActiveRecord::Rollback if @dry_run
      end

      Result.new(destroyed_orphans: destroyed_orphans, created_missing: created_missing, errors: errors)
    rescue => e
      @logger.error "[ReconcilePurchaseOrderLinksService] #{e.class}: #{e.message}"
      Result.new(destroyed_orphans: 0, created_missing: 0, errors: [e.message])
    end

    private

    def destroy_orphans
      orphan_scope = ::Inventory.where.not(purchase_order_id: nil)
                                .where("purchase_order_item_id IS NULL OR NOT EXISTS (SELECT 1 FROM purchase_order_items poi WHERE poi.id = inventories.purchase_order_item_id)")
      count = 0
      orphan_scope.limit(@limit).find_each do |inv|
        count += 1
        next if @dry_run
        begin
          inv_id = inv.id
          inv.destroy!
          ::InventoryEvent.create!(inventory_id: inv_id, product_id: inv.product_id, event_type: 'reconciliation_orphan_destroyed', metadata: { purchase_order_id: inv.purchase_order_id }) rescue nil
        rescue => e
          @logger.error "[ReconcilePurchaseOrderLinksService#destroy_orphans] inv=#{inv.id} #{e.class}: #{e.message}"
        end
      end
      count
    end

    def create_missing
      created = 0
      PurchaseOrderItem.find_each do |poi|
        existing = ::Inventory.where(purchase_order_item_id: poi.id).count
        needed = poi.quantity.to_i - existing
        next if needed <= 0
        needed.times do
          created += 1
          break if created >= @limit
          next if @dry_run
          begin
            inv = ::Inventory.create!(
              product_id: poi.product_id,
              purchase_order_id: poi.purchase_order_id,
              purchase_order_item_id: poi.id,
              purchase_cost: poi.unit_compose_cost_in_mxn.to_f.nonzero? || poi.unit_cost.to_f,
              status: :in_transit,
              status_changed_at: Time.current,
              source: 'po_regular'
            )
            ::InventoryEvent.create!(inventory_id: inv.id, product_id: poi.product_id, event_type: 'reconciliation_missing_created', metadata: { purchase_order_id: poi.purchase_order_id, purchase_order_item_id: poi.id }) rescue nil
          rescue => e
            @logger.error "[ReconcilePurchaseOrderLinksService#create_missing] poi=#{poi.id} #{e.class}: #{e.message}"
          end
        end
      end
      created
    end
  end
end
