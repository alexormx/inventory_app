class Admin::InventoryAuditsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    @status_counts = Inventory.group(:status).count
    @inconsistencies = Inventory
      .where.not(sale_order_id: nil)
      .where(status: [:available, :in_transit])
      .includes(:product)
      .order(:product_id, :status, :id)
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
