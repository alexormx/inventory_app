# frozen_string_literal: true

module Products
  # Red de seguridad para la auto-pausa. Los callbacks de Inventory pausan en
  # tiempo real, pero un fallo (excepción tragada, escritura por SQL crudo,
  # import masivo con update_columns) puede dejar un producto `active` sin stock
  # publicable. Este job recorre periódicamente los activos y pausa los que ya
  # no son publicables.
  #
  # SOLO pausa. Nunca reactiva: la republicación pasa por la cola de revisión
  # del admin (decisión de negocio, no automática).
  class ReconcilePublicationJob < ApplicationJob
    queue_as :default

    def perform
      paused = 0
      unpublishable_active_product_ids.each do |product_id|
        product = Product.find_by(id: product_id)
        next unless product

        # auto_pause_if_unpublishable! revalida con la lógica canónica, así que
        # un producto que sí es elegible no se pausa aunque la consulta lo
        # incluyera por una carrera entre el scan y el commit.
        before = product.status
        product.auto_pause_if_unpublishable!
        paused += 1 if before != product.reload.status
      end

      Rails.logger.info("[Products::ReconcilePublicationJob] paused=#{paused}")
      paused
    end

    private

    # Productos `active` que NO permiten preventa/backorder y NO tienen ninguna
    # pieza publicable (libre con ubicación, o en tránsito). Una sola consulta.
    def unpublishable_active_product_ids
      avail = Inventory.statuses[:available]
      transit = Inventory.statuses[:in_transit]

      publishable_product_ids =
        Inventory.where(sale_order_id: nil)
                 .where(
                   '(status = :avail AND inventory_location_id IS NOT NULL) OR status = :transit',
                   avail: avail, transit: transit
                 )
                 .distinct
                 .pluck(:product_id)

      scope = Product.where(status: 'active')
                     .where(preorder_available: false, backorder_allowed: false)
      scope = scope.where.not(id: publishable_product_ids) if publishable_product_ids.any?
      scope.pluck(:id)
    end
  end
end
