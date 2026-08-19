# frozen_string_literal: true

module Admin
  # Orquesta el lote de ubicación: elegir estante, ir agregando productos y
  # confirmar todo junto. Toda la seguridad (elegibilidad, FIFO, bloqueo,
  # todo-o-nada, auditoría) vive en los servicios; aquí sólo se arma la lista.
  class LocationAssignmentBatchesController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    # Un lote tiene UNA ubicación. Cambiarla con productos dentro se confirma
    # antes, para no acabar con un lote mezclado sin querer.
    def set_location
      if batch.location_id.present? && batch.location_id.to_s != params[:location_id].to_s && !batch.empty?
        unless ActiveModel::Type::Boolean.new.cast(params[:confirm_change])
          return redirect_back_to_page(
            alert: "Ya tienes #{batch.total_units} pieza(s) preparadas para " \
                   "#{batch.location&.full_path}. Vacía el lote si quieres cambiar de ubicación."
          )
        end

        batch.clear_lines
      end

      batch.location = params[:location_id]
      redirect_back_to_page(notice: batch.location ? "Ubicación seleccionada: #{batch.location.full_path}." : nil)
    end

    # Al agregar bien se limpia el buscador: el trabajo es en cadena —SKU, agregar,
    # siguiente SKU— y dejar el término anterior obliga a borrarlo a mano cada vez.
    # Si algo falla se conserva lo tecleado (término y cantidad) para poder
    # corregirlo sin volver a buscar.
    def add_line
      return retry_page(alert: 'Selecciona primero la ubicación destino.') if batch.location_id.blank?

      quantity = Integer(params[:quantity].to_s.strip, 10)
      raise ArgumentError unless quantity.positive?

      product = Product.find_by(id: params[:product_id])
      return retry_page(alert: 'El producto no existe.') unless product

      batch.add(product.id, quantity)
      redirect_back_to_page(notice: "#{quantity} × #{product.product_name} agregado al lote.",
                            clear_search: true)
    rescue ArgumentError, TypeError
      retry_page(alert: 'La cantidad debe ser un número entero mayor a cero.')
    rescue Admin::LocationAssignmentBatch::TooManyLines
      retry_page(alert: "El lote admite hasta #{Admin::LocationAssignmentBatch::MAX_LINES} productos.")
    end

    def update_line
      batch.set_quantity(params[:product_id], params[:quantity])
      redirect_back_to_page
    end

    def remove_line
      batch.remove(params[:product_id])
      redirect_back_to_page(notice: 'Producto quitado del lote.')
    end

    def clear
      batch.clear
      redirect_back_to_page(notice: 'Lote vaciado.')
    end

    def review
      return redirect_back_to_page(alert: 'Agrega al menos un producto para revisar.') if batch.empty?
      return redirect_back_to_page(alert: 'Selecciona la ubicación destino.') if batch.location.blank?

      @location = batch.location
      @lines = batch.detailed_lines
      @total_units = batch.total_units
    end

    # Confirmación única del lote completo. Si algo no alcanza, no se guarda nada.
    def confirm
      result = Inventories::BulkAssignLocationBatchService.call(
        lines: batch.service_lines,
        location_id: batch.location_id,
        actor: current_user
      )

      detail = result.lines.map { |l| "#{l[:inventories].size} #{l[:product].product_name}" }.join(', ')
      batch.clear
      redirect_to admin_inventory_unlocated_path,
                  notice: "#{result.assigned_count} unidades fueron asignadas a " \
                          "#{result.location.full_path}: #{detail}.",
                  status: :see_other
    rescue Inventories::BulkAssignLocationBatchService::InsufficientEligibleInventory => e
      redirect_to admin_location_assignment_batch_review_path, alert: e.message, status: :see_other
    rescue Inventories::BulkAssignLocationBatchService::Error,
           Inventories::LocationAssignment::InvalidLocation => e
      redirect_to admin_inventory_unlocated_path, alert: e.message, status: :see_other
    end

    private

    def batch = @batch ||= Admin::LocationAssignmentBatch.new(session)

    def redirect_back_to_page(notice: nil, alert: nil, clear_search: false, extra: {})
      query = clear_search ? {} : { q: params[:q].presence }
      redirect_to admin_inventory_unlocated_path(**query.compact, **extra.compact),
                  notice: notice, alert: alert, status: :see_other
    end

    # Vuelve a la página conservando lo que el operador tenía escrito, para que
    # sólo tenga que corregir el dato que falló.
    def retry_page(alert:)
      redirect_back_to_page(alert: alert,
                            extra: { retry_product_id: params[:product_id].presence,
                                     retry_quantity: params[:quantity].presence })
    end
  end
end
