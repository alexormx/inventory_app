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

    JOB_NAME = 'products.reconcile_publication'

    # Acepta un run_id opcional (cuando lo dispara un controlador) o crea su
    # propia corrida (cuando lo dispara el schedule recurrente). En ambos casos
    # el resultado queda en MaintenanceRun, visible en /admin/settings.
    def perform(run_id = nil)
      run = run_id ? MaintenanceRun.find_by(id: run_id) : MaintenanceRun.create!(job_name: JOB_NAME, status: :queued)
      run&.update!(status: :running, started_at: Time.current)

      candidate_ids = unpublishable_active_product_ids
      paused_products = []

      candidate_ids.each do |product_id|
        product = Product.find_by(id: product_id)
        next unless product

        # auto_pause_if_unpublishable! revalida con la lógica canónica, así que
        # un producto que sí es elegible no se pausa aunque la consulta lo
        # incluyera por una carrera entre el scan y el commit.
        before = product.status
        product.auto_pause_if_unpublishable!
        paused_products << { id: product.id, name: product.product_name } if before != product.reload.status
      end

      stats = { scanned: candidate_ids.size, paused: paused_products.size, products: paused_products }
      run&.update!(status: :completed, finished_at: Time.current, stats: stats)
      Rails.logger.info("[Products::ReconcilePublicationJob] scanned=#{candidate_ids.size} paused=#{paused_products.size}")
      paused_products.size
    rescue StandardError => e
      run&.update!(status: :failed, finished_at: Time.current, error: "#{e.class}: #{e.message}")
      Rails.logger.error("[Products::ReconcilePublicationJob] #{e.class}: #{e.message}")
      raise
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
