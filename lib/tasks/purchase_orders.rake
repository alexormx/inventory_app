# frozen_string_literal: true

namespace :purchase_orders do
  desc "Recalcula costos compose/alpha para todas las PurchaseOrderItems de todos los productos"
  task recalc_all_costs: :environment do
    puts "[PO] Recalculando costos globales..."
    result = PurchaseOrders::RecalculateAllCostsService.new.call
    puts "Productos escaneados: #{result.products_scanned}"
    puts "Items escaneados:    #{result.items_scanned}"
    puts "Items actualizados:  #{result.items_updated}"
    if result.errors.any?
      puts "Errores (#{result.errors.size}):"
      result.errors.first(20).each { |e| puts "  - #{e}" }
      puts "(Mostrando primeros 20)" if result.errors.size > 20
    else
      puts "Sin errores"
    end
    puts "Listo"
  end

  desc "Recalcula distribución proporcional de costos (volumen/peso) para un producto específico: PRODUCT_ID=123"
  task recalc_distributed_for_product: :environment do
    pid = ENV["PRODUCT_ID"]
    abort "Debe proporcionar PRODUCT_ID" if pid.blank?
    product = Product.find_by(id: pid) or abort "Producto #{pid} no encontrado"
    puts "[PO] Recalculando distribución para producto #{product.id}..."
    result = PurchaseOrders::RecalculateDistributedCostsForProductService.new(product).call
    puts "POs escaneadas: #{result.purchase_orders_scanned}"
    puts "Items recalculados: #{result.items_recalculated}"
    if result.errors.any?
      puts "Errores (#{result.errors.size}):"
      result.errors.each { |e| puts "  - #{e}" }
    else
      puts "Sin errores"
    end
  end

  desc "Recalcula distribución proporcional para TODOS los productos (puede tardar)"
  task recalc_distributed_all: :environment do
    puts "[PO] Recalculando distribución para todos los productos..."
    total_po = 0
    total_items = 0
    errors = []
    Product.find_in_batches(batch_size: 300) do |batch|
      batch.each do |product|
        r = PurchaseOrders::RecalculateDistributedCostsForProductService.new(product).call
        total_po += r.purchase_orders_scanned
        total_items += r.items_recalculated
        errors.concat(r.errors) if r.errors.any?
      end
    end
    puts "POs escaneadas: #{total_po}"
    puts "Items recalculados: #{total_items}"
    if errors.any?
      puts "Errores (#{errors.size}):"
      errors.first(30).each { |e| puts "  - #{e}" }
      puts "(Mostrando primeros 30)" if errors.size > 30
    else
      puts "Sin errores"
    end
    puts "Listo"
  end
end
