class Admin::SaleOrdersAuditsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    # Estados de inventario que cuentan como "asignados" a una SO
    assigned_statuses = Inventory.statuses.values_at('reserved', 'sold', 'pre_reserved', 'pre_sold')

    # Query: líneas cuya cantidad NO está totalmente cubierta por (inventario asignado + preorder + backorder)
    mismatches = SaleOrderItem
      .joins(:sale_order)
      .joins(<<~SQL)
        LEFT JOIN inventories inv
          ON inv.sale_order_id = sale_order_items.sale_order_id
         AND inv.product_id    = sale_order_items.product_id
      SQL
      .where("inv.id IS NULL OR inv.status IN (?)", assigned_statuses)
      .select(
        'sale_order_items.*',
        'sale_orders.user_id as so_user_id',
        'COUNT(inv.id) AS assigned_inv_count'
      )
      .group('sale_order_items.id')
      .having('COALESCE(COUNT(inv.id),0) + COALESCE(sale_order_items.preorder_quantity,0) + COALESCE(sale_order_items.backordered_quantity,0) < sale_order_items.quantity')

    @lines_with_gap = mismatches.includes(:product, :sale_order).order('sale_order_items.sale_order_id DESC')

    # Resumen
    total_lines = SaleOrderItem.count
    audited_lines = @lines_with_gap.size
    missing_units = @lines_with_gap.sum do |li|
      assigned = li.attributes['assigned_inv_count'].to_i
      preorder = li.preorder_quantity.to_i
      backord  = li.backordered_quantity.to_i
      [li.quantity.to_i - (assigned + preorder + backord), 0].max
    end
    @summary = {
      total_lines: total_lines,
      lines_with_gap: audited_lines,
      missing_units: missing_units
    }
  end

  # Corrige faltantes: asigna inventario disponible a las líneas con gap;
  # si no alcanza, crea reservas de preventa (PreorderReservation) y actualiza preorder_quantity.
  def fix_gaps
    dry_run = ActiveModel::Type::Boolean.new.cast(params[:dry_run])

    assigned_statuses = Inventory.statuses.values_at('reserved', 'sold', 'pre_reserved', 'pre_sold')

    mismatches = SaleOrderItem
      .joins(:sale_order)
      .joins(<<~SQL)
        LEFT JOIN inventories inv
          ON inv.sale_order_id = sale_order_items.sale_order_id
         AND inv.product_id    = sale_order_items.product_id
      SQL
      .where("inv.id IS NULL OR inv.status IN (?)", assigned_statuses)
      .select('sale_order_items.id')
      .group('sale_order_items.id')
      .having('COALESCE(COUNT(inv.id),0) + COALESCE(sale_order_items.preorder_quantity,0) + COALESCE(sale_order_items.backordered_quantity,0) < sale_order_items.quantity')

    ids = mismatches.pluck(:id)

  lines_processed    = 0
  units_assigned_avl = 0
  units_assigned_it  = 0
  units_preordered   = 0

    SaleOrderItem.where(id: ids).includes(:sale_order, :product).find_each do |li|
      so = li.sale_order
      # Calcular faltante actual por línea
      assigned_count = Inventory.where(sale_order_id: so.id, product_id: li.product_id, status: [:reserved, :sold, :pre_reserved, :pre_sold]).count
      missing = li.quantity.to_i - (assigned_count + li.preorder_quantity.to_i + li.backordered_quantity.to_i)
      next if missing <= 0

      # 1) Asignar inventario disponible (solo status: available)
  available_scope = Inventory.where(product_id: li.product_id, status: :available, sale_order_id: nil)
                                 .order(:status_changed_at)
                                 .limit(missing)
      assignable = available_scope.to_a
      if dry_run
        units_assigned_avl += assignable.size
      else
        assignable.each do |inv|
          inv.update!(
            status: :reserved,
            sale_order_id: so.id,
            sale_order_item_id: li.id,
            status_changed_at: Time.current,
            sold_price: li.unit_final_price.to_f.nonzero? || inv.sold_price
          )
        end
        units_assigned_avl += assignable.size
      end

      remaining = missing - assignable.size

      # 1b) Usar in_transit -> asignar como pre_* (según estado de SO) si aún falta
      if remaining > 0
        it_scope = Inventory.where(product_id: li.product_id, status: :in_transit, sale_order_id: nil)
                            .order(:status_changed_at)
                            .limit(remaining)
        in_transit_items = it_scope.to_a
        if dry_run
          units_assigned_it += in_transit_items.size
        else
          in_transit_items.each do |inv|
            target_status = (so.status == "Confirmed") ? :pre_sold : :pre_reserved
            inv.update!(
              status: target_status,
              sale_order_id: so.id,
              sale_order_item_id: li.id,
              status_changed_at: Time.current,
              sold_price: li.unit_final_price.to_f.nonzero? || inv.sold_price
            )
          end
          units_assigned_it += in_transit_items.size
        end
        remaining -= in_transit_items.size
      end
      if remaining > 0
        if dry_run
          units_preordered += remaining
        else
          # Crear una reserva de preventa y reflejarlo en la línea
          PreorderReservation.create!(
            product: li.product,
            user: so.user,
            sale_order: so,
            quantity: remaining,
            status: :pending,
            reserved_at: Time.current
          )
          li.update!(preorder_quantity: li.preorder_quantity.to_i + remaining)
          units_preordered += remaining
        end
      end

      lines_processed += 1
    end

    if dry_run
      redirect_to admin_sale_orders_audit_path, notice: "Simulación: asignar avl=#{units_assigned_avl}, in_transit=#{units_assigned_it}; crear preventa para #{units_preordered} en #{lines_processed} línea(s)."
    else
      redirect_to admin_sale_orders_audit_path, notice: "Corrección aplicada: asignadas avl=#{units_assigned_avl}, in_transit=#{units_assigned_it}; preventa creada para #{units_preordered} en #{lines_processed} línea(s)."
    end
  end
end
