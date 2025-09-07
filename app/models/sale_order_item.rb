class SaleOrderItem < ApplicationRecord
  include InventorySyncable

  belongs_to :sale_order
  belongs_to :product

  validates :quantity, presence: true, numericality: { greater_than: 0 }
  validates :unit_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_line_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :preorder_quantity, :backordered_quantity, numericality: { greater_than_or_equal_to: 0 }
  validate :pending_quantities_not_exceed_total

  after_save :sync_inventory_records, if: :saved_change_to_quantity?
  after_commit :update_product_stats
  after_commit :recalculate_parent_order_totals
  after_commit :backfill_inventory_links
  after_destroy_commit :recalculate_parent_order_totals
  after_destroy :cleanup_preorders_and_preassignments

  # ------ Métricas de volumen y peso ------
  # Asumimos que total_line_volume y total_line_weight ya representan (volumen_cm3, peso_gr) por la cantidad.
  # Si en algún momento se desea derivar desde dimensiones del producto, aquí sería el lugar.
  def volume_cm3
    return total_line_volume.to_d if total_line_volume.present?
    # Fallback: producto dimensiones * quantity
    if product.respond_to?(:unit_volume_cm3)
      (product.unit_volume_cm3 * quantity.to_i).to_d
    else
      0.to_d
    end
  end

  def weight_gr
    return total_line_weight.to_d if total_line_weight.present?
    if product.respond_to?(:unit_weight_gr)
      (product.unit_weight_gr * quantity.to_i).to_d
    else
      0.to_d
    end
  end

  # ------ Inventario asignado a esta línea (helpers) ------
  def inventory_units
    @inventory_units ||= Inventory.where(sale_order_id: sale_order_id, product_id: product_id)
  end

  def reserved_inventory_count
    inventory_units.count
  end

  def missing_inventory_units
    [quantity.to_i - reserved_inventory_count, 0].max
  end

  def immediate_quantity
    quantity.to_i - preorder_quantity.to_i - backordered_quantity.to_i
  end

  def pending?
    preorder_quantity.to_i.positive? || backordered_quantity.to_i.positive?
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
  sold_count    = so_inventory.where(status: Inventory.statuses[:sold]).count
  reserved_count = so_inventory.where(status: Inventory.statuses[:reserved]).count

    # No puedo “quitar” vendidos; solo puedo liberar reservados.
    if reserved_count < to_remove
      errors.add(:base, "No hay suficientes unidades reservadas para reducir #{to_remove}. "\
                        "(Vendidas: #{sold_count}, Reservadas: #{reserved_count})")
      throw :abort
    end
  end

  def ensure_no_sold_and_release_reserved
  sold = so_inventory.where(status: Inventory.statuses[:sold])
    if sold.exists?
  errors.add(:base, "No se puede eliminar la línea: tiene #{sold.count} unidad(es) vendida(s). Para poder eliminarla primero regresa la orden a 'Pending' (puede requerir pasar por 'Confirmed') para revertir vendido→reservado y luego intenta de nuevo.")
      throw :abort
    end

    # Libera las reservadas de esta línea
  so_inventory.where(status: Inventory.statuses[:reserved]).update_all(
      status: Inventory.statuses[:available],
      sale_order_id: nil,
  sale_order_item_id: nil,
      status_changed_at: Time.current,
      updated_at: Time.current
    )
  end

  # Al eliminar una línea, cancelar preventas ligadas y revertir pre_* en inventario
  def cleanup_preorders_and_preassignments
    begin
      # 1) Cancelar PreorderReservation vinculadas a esta SO y producto
      cancelled = PreorderReservation.statuses[:cancelled]
      PreorderReservation.where(sale_order_id: sale_order_id, product_id: product_id)
                         .update_all(status: cancelled, cancelled_at: Time.current, updated_at: Time.current)

      # 2) Revertir inventario pre_* a in_transit (y limpiar vínculos a SO)
      pre_reserved = Inventory.statuses[:pre_reserved]
      pre_sold     = Inventory.statuses[:pre_sold]
      in_transit   = Inventory.statuses[:in_transit]
      Inventory.where(sale_order_id: sale_order_id, product_id: product_id, status: [pre_reserved, pre_sold])
               .update_all(status: in_transit, sale_order_id: nil, sale_order_item_id: nil, status_changed_at: Time.current, updated_at: Time.current)
  # Intentar asignar preventas si hubiera pendientes y ahora hay inventario libre/in_transit
  Preorders::PreorderAllocator.new(product).call
    rescue => e
      Rails.logger.error "[SOI#cleanup_preorders_and_preassignments] #{e.class}: #{e.message}"
    end
  end

  # Luego de confirmar la eliminación, intenta asignar preventas pendientes con el inventario liberado
  after_destroy_commit :allocate_preorders_after_release

  def allocate_preorders_after_release
    begin
      Preorders::PreorderAllocator.new(product).call
    rescue => e
      Rails.logger.error "[SOI#allocate_preorders_after_release] #{e.class}: #{e.message}"
    end
  end

  # Asegura que toda pieza ligada a (SO, producto) tenga el sale_order_item_id correcto
  def backfill_inventory_links
    return unless sale_order_id.present? && product_id.present?
    Inventory.where(sale_order_id: sale_order_id, product_id: product_id, sale_order_item_id: nil)
             .update_all(sale_order_item_id: id, updated_at: Time.current)
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

  def pending_quantities_not_exceed_total
    if preorder_quantity.to_i + backordered_quantity.to_i > quantity.to_i
      errors.add(:base, "La suma de cantidades pendientes excede la cantidad total")
    end
  end

  # FUTURO: Soporte para backorders
end
