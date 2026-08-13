# frozen_string_literal: true

module Admin
  module InventoryVerificationsHelper
    STATUS_LABELS = {
      'available' => 'Disponible',
      'reserved' => 'Reservado',
      'damaged' => 'Dañado',
      'lost' => 'Perdido'
    }.freeze
    RESULT_LABELS = {
      'found' => 'Encontrado',
      'damaged' => 'Dañado',
      'missing' => 'Faltante'
    }.freeze
    SNAPSHOT_FIELD_LABELS = {
      'updated_at' => 'Fecha de actualización',
      'status' => 'Estado',
      'inventory_location_id' => 'Ubicación',
      'sale_order_id' => 'Orden de venta',
      'sale_order_item_id' => 'Partida de venta',
      'product_id' => 'Producto'
    }.freeze

    def inventory_verification_status_label(status)
      STATUS_LABELS.fetch(status.to_s, status.to_s.humanize)
    end

    def inventory_verification_status_class(status)
      {
        'available' => 'text-bg-success',
        'reserved' => 'text-bg-warning',
        'damaged' => 'text-bg-warning',
        'lost' => 'text-bg-danger'
      }.fetch(status.to_s, 'text-bg-secondary')
    end

    def inventory_verification_result_label(result)
      RESULT_LABELS.fetch(result.to_s, result.to_s.humanize)
    end

    def inventory_snapshot_field_label(field)
      SNAPSHOT_FIELD_LABELS.fetch(field.to_s, field.to_s.humanize)
    end

    def inventory_verification_location_label(location_id, locations)
      return 'Sin ubicación' if location_id.blank?

      location = locations[location_id.to_i]
      return "Ubicación ##{location_id} (ya no disponible)" unless location

      "#{location.full_path} (#{location.code}) · Ubicación ##{location.id}"
    end
  end
end
