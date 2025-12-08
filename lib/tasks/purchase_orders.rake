# frozen_string_literal: true

namespace :purchase_orders do
  desc 'Recalcula costos compose/alpha para todas las PurchaseOrderItems de todos los productos'
  task recalc_all_costs: :environment do
    puts '[PO] Recalculando costos globales...'
    result = PurchaseOrders::RecalculateAllCostsService.new.call
    puts "Productos escaneados: #{result.products_scanned}"
    puts "Items escaneados:    #{result.items_scanned}"
    puts "Items actualizados:  #{result.items_updated}"
    if result.errors.any?
      puts "Errores (#{result.errors.size}):"
      result.errors.first(20).each { |e| puts "  - #{e}" }
      puts '(Mostrando primeros 20)' if result.errors.size > 20
    else
      puts 'Sin errores'
    end
    puts 'Listo'
  end

  desc 'Recalcula distribución proporcional de costos (volumen/peso) para un producto específico: PRODUCT_ID=123'
  task recalc_distributed_for_product: :environment do
    pid = ENV.fetch('PRODUCT_ID', nil)
    abort 'Debe proporcionar PRODUCT_ID' if pid.blank?
    product = Product.find_by(id: pid) or abort "Producto #{pid} no encontrado"
    puts "[PO] Recalculando distribución para producto #{product.id}..."
    result = PurchaseOrders::RecalculateDistributedCostsForProductService.new(product).call
    puts "POs escaneadas: #{result.purchase_orders_scanned}"
    puts "Items recalculados: #{result.items_recalculated}"
    if result.errors.any?
      puts "Errores (#{result.errors.size}):"
      result.errors.each { |e| puts "  - #{e}" }
    else
      puts 'Sin errores'
    end
  end

  desc 'Recalcula distribución proporcional para TODOS los productos (puede tardar)'
  task recalc_distributed_all: :environment do
    puts '[PO] Recalculando distribución para todos los productos...'
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
      puts '(Mostrando primeros 30)' if errors.size > 30
    else
      puts 'Sin errores'
    end
    puts 'Listo'
  end

  desc 'Reconciliar inventario vs purchase_order_items (crea faltantes y elimina huérfanos)'
  task reconcile_inventory: :environment do
    dry = ENV['DRY_RUN'] == '1'
    mode = (ENV['MODE'] || 'all').to_sym
    service = InventoryReconciliation::ReconcilePurchaseOrderLinksService.new(dry_run: dry, mode: mode)
    result = service.call
    puts "[reconcile_inventory] mode=#{mode} destroyed_orphans=#{result.destroyed_orphans} created_missing=#{result.created_missing} errors=#{result.errors.inspect} dry_run=#{dry}"
  end

  desc 'Marca POs con costs_distributed_at basándose en evidencias (líneas con total_line_cost y suma coincide)'
  task mark_distributed_costs: :environment do
    dry_run = ENV['DRY_RUN'] == '1'
    tolerance = (ENV['TOLERANCE'] || '0.01').to_f

    candidates = []
    skipped = []

    puts '[mark_distributed_costs] Escaneando Purchase Orders...'
    puts "DRY_RUN: #{dry_run}"
    puts "Tolerancia: #{tolerance}"

    PurchaseOrder.where(costs_distributed_at: nil).find_each do |po|
      lines = po.purchase_order_items.to_a

      # Saltar si no tiene líneas
      if lines.empty?
        skipped << { id: po.id, reason: 'sin_lineas' }
        next
      end

      # Saltar si alguna línea NO tiene total_line_cost
      unless lines.all? { |li| li.total_line_cost.present? }
        skipped << { id: po.id, reason: 'lineas_sin_total_line_cost' }
        next
      end

      # Calcular suma de líneas
      sum_lines = lines.sum { |li| li.total_line_cost.to_d }

      # Verificar si suma coincide con total_order_cost o subtotal (con tolerancia)
      matches_total = (sum_lines - po.total_order_cost.to_d).abs <= tolerance
      matches_subtotal = (sum_lines - po.subtotal.to_d).abs <= tolerance

      if matches_total || matches_subtotal
        candidates << {
          id: po.id,
          sum_lines: sum_lines,
          total_order_cost: po.total_order_cost,
          subtotal: po.subtotal,
          matched: matches_total ? 'total' : 'subtotal',
          updated_at: po.updated_at
        }
      else
        skipped << {
          id: po.id,
          reason: 'suma_no_coincide',
          sum_lines: sum_lines,
          total: po.total_order_cost,
          subtotal: po.subtotal
        }
      end
    end

    puts "\n=== RESULTADOS ==="
    puts "Candidatas para marcar: #{candidates.count}"
    puts "Omitidas: #{skipped.count}"

    if candidates.any?
      puts "\n=== MUESTRA DE CANDIDATAS (primeras 10) ==="
      candidates.first(10).each do |c|
        puts "  PO #{c[:id]}: sum_lines=#{c[:sum_lines]} vs #{c[:matched]}=#{c[c[:matched].to_sym]} | updated_at=#{c[:updated_at]}"
      end
    end

    if skipped.any?
      puts "\n=== MUESTRA DE OMITIDAS (primeras 10) ==="
      skipped.first(10).each do |s|
        if s[:reason] == 'suma_no_coincide'
          puts "  PO #{s[:id]}: #{s[:reason]} (sum=#{s[:sum_lines]} vs total=#{s[:total]} subtotal=#{s[:subtotal]})"
        else
          puts "  PO #{s[:id]}: #{s[:reason]}"
        end
      end
    end

    if dry_run
      puts "\n=== DRY RUN: No se aplicaron cambios ==="
      puts 'Ejecuta con DRY_RUN=0 para aplicar los cambios.'
    else
      puts "\n=== APLICANDO CAMBIOS ==="
      count = 0
      candidates.each do |c|
        po = PurchaseOrder.find(c[:id])
        # Usar updated_at para reflejar cuándo se editó por última vez
        po.update_column(:costs_distributed_at, po.updated_at || Time.current)
        count += 1
      end
      puts "✅ Marcadas #{count} Purchase Orders con costs_distributed_at"
    end

    puts "\nListo."
  end
end
