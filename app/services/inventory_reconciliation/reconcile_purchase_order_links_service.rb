# frozen_string_literal: true

module InventoryReconciliation
  class ReconcilePurchaseOrderLinksService
    Result = Struct.new(:destroyed_orphans, :created_missing, :errors, keyword_init: true)

    def initialize(dry_run: false, limit: 10_000, logger: Rails.logger, mode: :all)
      @dry_run = dry_run
      @limit = limit
      @logger = logger
      @mode = (mode || :all).to_sym
    end

    def call
      destroyed_orphans = 0
      created_missing = 0
      errors = []

      ActiveRecord::Base.transaction do
        destroyed_orphans += destroy_orphans if process_orphans?
        created_missing += create_missing if process_missing?
        raise ActiveRecord::Rollback if @dry_run
      end

      Result.new(destroyed_orphans: destroyed_orphans, created_missing: created_missing, errors: errors)
    rescue StandardError => e
      @logger.error "[ReconcilePurchaseOrderLinksService] #{e.class}: #{e.message}"
      Result.new(destroyed_orphans: 0, created_missing: 0, errors: [e.message])
    end

    private

    # Huérfana: pieza viva (no retirada) cuya línea de compra ya no existe.
    # Una pieza de cliente nunca se toca. La que tiene historial se retira a
    # :scrap en vez de borrarse (InventoryEvent/InventoryAssignmentLog tienen
    # llave foránea hacia ella). Cada pieza va en su propio savepoint: en
    # PostgreSQL un error aborta la transacción entera, y antes una sola pieza
    # con historial dejaba la corrida completa en 0.
    def destroy_orphans
      orphan_scope = ::Inventory.where.not(purchase_order_id: nil)
                                .where.not(status: :scrap)
                                .where(sale_order_id: nil)
                                .where.not(status: InventorySyncable::COMMITTED_INVENTORY_STATUSES)
                                .where('purchase_order_item_id IS NULL OR NOT EXISTS (SELECT 1 FROM purchase_order_items poi WHERE poi.id = inventories.purchase_order_item_id)')
      count = 0
      orphan_scope.limit(@limit).find_each do |inv|
        count += 1
        next if @dry_run

        ::ActiveRecord::Base.transaction(requires_new: true) do
          ::Product.lock.find(inv.product_id)
          history?(inv) ? retire_orphan!(inv) : inv.destroy!
        end
      rescue StandardError => e
        count -= 1
        @logger.error "[ReconcilePurchaseOrderLinksService#destroy_orphans] inv=#{inv.id} #{e.class}: #{e.message}"
      end
      count
    end

    def history?(inv)
      ::InventoryEvent.exists?(inventory_id: inv.id) || ::InventoryAssignmentLog.exists?(inventory_id: inv.id)
    end

    def retire_orphan!(inv)
      previous_status = inv.status
      inv.defer_preorder_reconciliation = true
      inv.update!(status: :scrap, status_changed_at: Time.current)
      ::InventoryEvent.create!(inventory: inv, product_id: inv.product_id, event_type: 'status_change',
                               metadata: { 'reason' => 'reconciliation_orphan_retired',
                                           'previous_status' => previous_status, 'new_status' => 'scrap',
                                           'purchase_order_id' => inv.purchase_order_id,
                                           'purchase_order_item_id' => inv.purchase_order_item_id })
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
            begin
              ::InventoryEvent.create!(inventory_id: inv.id, product_id: poi.product_id, event_type: 'reconciliation_missing_created',
                                       metadata: { purchase_order_id: poi.purchase_order_id, purchase_order_item_id: poi.id })
            rescue StandardError
              nil
            end
          rescue StandardError => e
            @logger.error "[ReconcilePurchaseOrderLinksService#create_missing] poi=#{poi.id} #{e.class}: #{e.message}"
          end
        end
      end
      created
    end

    def process_orphans?
      @mode == :all || @mode == :orphans
    end

    def process_missing?
      @mode == :all || @mode == :missing
    end
  end
end
