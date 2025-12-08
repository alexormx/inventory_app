# frozen_string_literal: true

module PurchaseOrders
  # Servicio unificado que ejecuta ambos recalculos:
  # 1. RecalculateCostsForProductService (cálculo simple alpha/compose heredado) si columnas existen
  # 2. RecalculateDistributedCostsForProductService (distribución por volumen + propagación inventario)
  # Además, si fue invocado tras cambio de dimensiones/peso puede recibir flag dimension_change: true
  # para registrar un InventoryEvent por cada inventario afectado (opcional granular, por ahora uno global).
  class RecalculateAllCostsForProductService
    Result = Struct.new(
      :product_id,
      :simple_items_scanned,
      :simple_items_updated,
      :distributed_purchase_orders_scanned,
      :distributed_items_recalculated,
      :errors,
      keyword_init: true
    )

    def initialize(product, dimension_change: false)
      @product = product
      @dimension_change = dimension_change
    end

    def call
      return empty_result('nil product') unless @product
      return empty_result('no id') unless @product.id

      errors = []
      simple_items_scanned = 0
      simple_items_updated = 0
      dist_po_scanned = 0
      dist_items_recalc = 0

      # 1) Recalculo simple si el servicio existe
      if defined?(PurchaseOrders::RecalculateCostsForProductService)
        begin
          r = PurchaseOrders::RecalculateCostsForProductService.new(@product).call
          simple_items_scanned = r.items_scanned
          simple_items_updated = r.items_updated
          errors.concat(r.errors) if r.errors.any?
        rescue StandardError => e
          errors << "simple: #{e.class}: #{e.message}"
        end
      end

      # 2) Recalculo distribuido
      if defined?(PurchaseOrders::RecalculateDistributedCostsForProductService)
        begin
          r2 = PurchaseOrders::RecalculateDistributedCostsForProductService.new(@product).call
          dist_po_scanned = r2.purchase_orders_scanned
          dist_items_recalc = r2.items_recalculated
          errors.concat(r2.errors) if r2.errors.any?
        rescue StandardError => e
          errors << "distributed: #{e.class}: #{e.message}"
        end
      end

      # 3) Evento agregado de dimensiones (global — no por inventario, para evitar spam)
      if @dimension_change
        begin
          begin
            InventoryEvent.create!(
              inventory: Inventory.where(product_id: @product.id).first, # puede ser nil si aún no hay inventario
              product: @product,
              event_type: 'product_dimensions_changed',
              metadata: {
                product_id: @product.id,
                length_cm: @product.length_cm,
                width_cm: @product.width_cm,
                height_cm: @product.height_cm,
                weight_gr: @product.weight_gr,
                distributed_purchase_orders_scanned: dist_po_scanned,
                distributed_items_recalculated: dist_items_recalc,
                simple_items_scanned: simple_items_scanned,
                simple_items_updated: simple_items_updated
              }
            )
          rescue StandardError
            nil
          end
        rescue StandardError => e
          errors << "event: #{e.class}: #{e.message}"
        end
      end

      Result.new(
        product_id: @product.id,
        simple_items_scanned: simple_items_scanned,
        simple_items_updated: simple_items_updated,
        distributed_purchase_orders_scanned: dist_po_scanned,
        distributed_items_recalculated: dist_items_recalc,
        errors: errors
      )
    end

    private

    def empty_result(msg = nil)
      Result.new(
        product_id: @product&.id,
        simple_items_scanned: 0,
        simple_items_updated: 0,
        distributed_purchase_orders_scanned: 0,
        distributed_items_recalculated: 0,
        errors: msg ? [msg] : []
      )
    end
  end
end
