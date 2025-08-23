class SaleOrderItem < ApplicationRecord
  include InventorySyncable

  belongs_to :sale_order
  belongs_to :product

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_line_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  after_save :sync_inventory_records, if: :saved_change_to_quantity?
  after_commit :update_product_stats
  after_commit :recalculate_parent_order_totals

  # ------ Métricas de volumen y peso ------
  # Asumimos que total_line_volume y total_line_weight ya representan (volumen_cm3, peso_gr) por la cantidad.
  # Si en algún momento se desea derivar desde dimensiones del producto, aquí sería el lugar.
  def volume_cm3
    total_line_volume.to_d
  end

  def weight_gr
    total_line_weight.to_d
  end

  # Guards de seguridad
  before_update  :ensure_free_to_reduce, if: :will_reduce_quantity?
  before_destroy :ensure_no_sold_and_release_reserved


  private

  def will_reduce_quantity?
    quantity_changed? && quantity_change_to_be_saved.first.to_i > quantity_change_to_be_saved.last.to_i
  end

  # Cuánto quiero quitar de la línea
  def desired_reduction
    old_qty, new_qty = quantity_change_to_be_saved
    old_qty.to_i - new_qty.to_i
  end

  # Scope de inventario ligado a esta SO y producto (sirve aunque no guardes sale_order_item_id)
  def so_inventory
    Inventory.where(sale_order_id: sale_order_id, product_id: product_id)
  end

  def ensure_free_to_reduce
    to_remove = desired_reduction
    sold_count    = so_inventory.where(status: %w[sold]).count
    reserved_count = so_inventory.where(status: %w[reserved]).count

    # No puedo “quitar” vendidos; solo puedo liberar reservados.
    if reserved_count < to_remove
      errors.add(:base, "No hay suficientes unidades reservadas para reducir #{to_remove}. "\
                        "(Vendidas: #{sold_count}, Reservadas: #{reserved_count})")
      throw :abort
    end
  end

  def ensure_no_sold_and_release_reserved
    sold = so_inventory.where(status: %w[sold])
    if sold.exists?
      errors.add(:base, "No se puede eliminar la línea: tiene #{sold.count} unidad(es) vendida(s).")
      throw :abort
    end

    # Libera las reservadas de esta línea
    so_inventory.where(status: %w[reserved]).update_all(
      status: Inventory.statuses[:available],
      sale_order_id: nil,
      status_changed_at: Time.current,
      updated_at: Time.current
    )
  end

  def update_product_stats
    Products::UpdateStatsService.new(product).call
  rescue => e
    Rails.logger.error "[SOI#update_product_stats] #{e.class}: #{e.message}"
  end

  def recalculate_parent_order_totals
    return unless sale_order_id.present?
    # Evitar recursión infinita: ejecuta fuera de transacción de la línea ya comprometida
    SaleOrder.find_by(id: sale_order_id)&.recalculate_totals!(persist: true)
  rescue => e
    Rails.logger.error "[SOI#recalculate_parent_order_totals] #{e.class}: #{e.message}"
  end

  # FUTURO: Soporte para backorders
end
