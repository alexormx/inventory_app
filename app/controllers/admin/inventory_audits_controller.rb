class Admin::InventoryAuditsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    @status_counts = Inventory.group(:status).count
    # 1) Piezas con SO pero estatus incongruente (available/in_transit)
    @inconsistencies = Inventory
      .where.not(sale_order_id: nil)
      .where(status: [:available, :in_transit])
      .includes(:product)
      .order(:product_id, :status, :id)

    # 2) Piezas con SO pero sin SO line (sale_order_item_id nulo)
    link_scope = Inventory.where.not(sale_order_id: nil).where(sale_order_item_id: nil)
    # agrupar por par para mostrar un resumen
    @missing_so_line_groups = link_scope
      .group(:sale_order_id, :product_id)
      .count
  end

  def fix_inconsistencies
    items = Inventory
      .where.not(sale_order_id: nil)
      .where(status: [:available, :in_transit])
    fixed = 0
    changes = Hash.new(0) # "from->to" => count
    dry = ActiveModel::Type::Boolean.new.cast(params[:dry_run])
    items.find_each do |inv|
      so = SaleOrder.find_by(id: inv.sale_order_id)
      next unless so
      target_status = suggested_status_for(inv, so)
      next if target_status.nil?
      if dry
        changes["#{inv.status}->#{target_status}"] += 1
        fixed += 1
      else
        inv.update!(status: target_status, status_changed_at: Time.current)
        changes["#{inv.status}->#{target_status}"] += 1
        fixed += 1
      end
    end
    summary = "Auditoría: #{dry ? 'simulación' : 'corregidos'} #{fixed} registro(s)."
    if changes.any?
      detail = changes.map { |k,v| "#{k}: #{v}" }.sort.join(', ')
      summary << " Detalle: #{detail}"
    end
    redirect_to admin_inventory_audit_path, notice: summary
  end

  def fix_missing_so_lines
    dry = ActiveModel::Type::Boolean.new.cast(params[:dry_run])
    scope = Inventory.where.not(sale_order_id: nil).where(sale_order_item_id: nil)
    pairs = scope.group(:sale_order_id, :product_id).pluck(:sale_order_id, :product_id)
    updated = 0
    skipped = 0
    errors = 0
    pairs.each do |so_id, pid|
      begin
        if dry
          # Simulación: contar cuántos actualizaría
          updated += scope.where(sale_order_id: so_id, product_id: pid).count
        else
          res = Inventories::BackfillSaleOrderItemId.new(scope: Inventory.where(sale_order_id: so_id, product_id: pid)).call
          updated += res.inventories_updated
          skipped += res.pairs_skipped
        end
      rescue => e
        errors += 1
      end
    end
    msg = dry ? "Simulación: actualizaría #{updated} piezas; pares omitidos #{skipped}." : "Actualizadas #{updated} piezas; pares omitidos #{skipped}."
    msg << " Errores: #{errors}." if errors > 0
    redirect_to admin_inventory_audit_path, notice: msg
  end

  private

  def suggested_status_for(inv, so)
    case inv.status
    when "available"
      so.status == "Confirmed" ? :sold : :reserved
    when "in_transit"
      so.status == "Confirmed" ? :pre_sold : :pre_reserved
    else
      nil
    end
  end
end
