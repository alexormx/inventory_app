# frozen_string_literal: true

module Inventories
  class BackfillSaleOrderItemId
    Result = Struct.new(:inventories_updated, :pairs_processed, :pairs_skipped, :errors, keyword_init: true)

    def initialize(scope: nil, dry_run: false, batch_size: 500)
      @scope = scope || Inventory.where.not(sale_order_id: nil)
      @dry_run = dry_run
      @batch_size = batch_size
      @errors = []
      @inventories_updated = 0
      @pairs_processed = 0
      @pairs_skipped = 0
    end

    def call
      # Agrupar por sale_order_id y product_id para encontrar su línea correspondiente
      grouped = @scope.where(sale_order_item_id: nil)
                      .select(:sale_order_id, :product_id)
                      .distinct

      grouped.find_each(batch_size: 200) do |row|
        so_id = row.sale_order_id
        product_id = row.product_id
        @pairs_processed += 1
        begin
          soi = SaleOrderItem.find_by(sale_order_id: so_id, product_id: product_id)
          unless soi
            @pairs_skipped += 1
            next
          end
          inv_scope = @scope.where(sale_order_id: so_id, product_id: product_id, sale_order_item_id: nil)
          count = inv_scope.count
          if count.zero?
            @pairs_skipped += 1
            next
          end
          unless @dry_run
            inv_scope.in_batches(of: @batch_size) do |batch|
              updated = batch.update_all(sale_order_item_id: soi.id, updated_at: Time.current)
              @inventories_updated += updated
            end
          end
        rescue StandardError => e
          @errors << "SO=#{so_id} product=#{product_id} #{e.class}: #{e.message}"
        end
      end
      Result.new(inventories_updated: @inventories_updated, pairs_processed: @pairs_processed, pairs_skipped: @pairs_skipped, errors: @errors)
    end
  end
end
