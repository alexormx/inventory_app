module PurchaseOrders
  # Servicio para recalcular costos y métricas dependientes de producto
  # para TODAS las PurchaseOrderItems de todos los productos. Útil tras
  # una migración o ajuste masivo de dimensiones/peso.
  #
  # Contrato:
  #   call -> Result con estadísticas globales.
  class RecalculateAllCostsService
    Result = Struct.new(
      :products_scanned,
      :items_scanned,
      :items_updated,
      :errors,
      keyword_init: true
    )

    def initialize(batch_size: 200)
      @batch_size = batch_size
    end

    def call
      products_scanned = 0
      items_scanned = 0
      items_updated = 0
      errors = []

      Product.find_in_batches(batch_size: 500) do |batch|
        batch.each do |product|
          products_scanned += 1
          begin
            r = PurchaseOrders::RecalculateCostsForProductService.new(product).call
            items_scanned += r.items_scanned
            items_updated += r.items_updated
            errors.concat(r.errors) if r.errors.any?
          rescue => e
            Rails.logger.error("[RecalculateAllCostsService] product=#{product.id} #{e.class}: #{e.message}")
            errors << "product #{product.id}: #{e.class}: #{e.message}"
          end
        end
      end

      Result.new(
        products_scanned: products_scanned,
        items_scanned: items_scanned,
        items_updated: items_updated,
        errors: errors
      )
    end
  end
end
