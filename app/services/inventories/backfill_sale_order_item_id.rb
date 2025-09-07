module Inventories
  class BackfillSaleOrderItemId
    Result = Struct.new(:pairs_processed, :inventories_updated, :pairs_skipped, :errors, keyword_init: true)

    def initialize(scope: Inventory.all, logger: Rails.logger)
      @scope = scope
      @logger = logger
    end

    def call(limit_pairs: nil)
      res = Result.new(pairs_processed: 0, inventories_updated: 0, pairs_skipped: 0, errors: [])

      # Tomar pares (SO, product) con sale_order_id presente y sale_order_item_id nulo
      pairs = @scope.where.not(sale_order_id: nil)
                    .where(sale_order_item_id: nil)
                    .group(:sale_order_id, :product_id)
                    .limit(limit_pairs)
                    .pluck(:sale_order_id, :product_id)

      pairs.each do |so_id, product_id|
        begin
          target_soi_id = choose_so_item_id(so_id, product_id)
          if target_soi_id.nil?
            res.pairs_skipped += 1
            next
          end

          updated = @scope.where(sale_order_id: so_id, product_id: product_id, sale_order_item_id: nil)
                           .update_all(sale_order_item_id: target_soi_id, updated_at: Time.current)
          res.inventories_updated += updated
          res.pairs_processed += 1
        rescue => e
          @logger.error "[BackfillSOI] pair (#{so_id},#{product_id}) error: #{e.class} #{e.message}"
          res.errors << { pair: [so_id, product_id], error: "#{e.class}: #{e.message}" }
        end
      end

      res
    end

    private
    # Heurística:
    # 1) Si hay un único SOI para (SO, producto), usarlo.
    # 2) Si hay varios, tomar el que ya tenga más inventories vinculados (max count), excluyendo NULL.
    # 3) Si ninguno tiene vínculos aún, tomar el de mayor quantity; si empata, el menor id.
    def choose_so_item_id(so_id, product_id)
      candidates = SaleOrderItem.where(sale_order_id: so_id, product_id: product_id).pluck(:id, :quantity)
      return nil if candidates.empty?
      return candidates.first.first if candidates.size == 1

      counts = Inventory.where(sale_order_id: so_id, product_id: product_id)
                        .where.not(sale_order_item_id: nil)
                        .group(:sale_order_item_id)
                        .count
      if counts.present?
        soi_id, _ = counts.max_by { |_, c| c }
        return soi_id
      end

      # Mayor quantity, luego menor id
      candidates.max_by { |id, qty| [qty.to_i, -id.to_i] }.first
    end
  end
end
