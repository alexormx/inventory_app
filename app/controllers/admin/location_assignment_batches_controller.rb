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
          return respond_with_page(
            alert: "Ya tienes #{batch.total_units} pieza(s) preparadas para " \
                   "#{batch.location&.full_path}. Vacía el lote si quieres cambiar de ubicación."
          )
        end

        batch.clear_lines
      end

      batch.location = params[:location_id]
      # Cambiar de estante mueve toda la pantalla: el encabezado, lo que ya hay
      # guardado ahí y el estado de cada botón Agregar. Por eso este es el único
      # stream que toca los resultados de la búsqueda.
      respond_with_page(notice: batch.location ? "Ubicación seleccionada: #{batch.location.full_path}." : nil)
    end

    # El buscador NO se limpia al agregar: de una misma búsqueda suelen salir
    # varios SKU que van al mismo estante, y volver a teclearla cada vez era el
    # gesto que sobraba. Si algo falla tampoco se toca nada, así que lo tecleado
    # se queda donde estaba para corregirlo.
    def add_line
      return retry_page(alert: 'Selecciona primero la ubicación destino.') if batch.location_id.blank?

      quantity = Integer(params[:quantity].to_s.strip, 10)
      raise ArgumentError unless quantity.positive?

      product = Product.find_by(id: params[:product_id])
      return retry_page(alert: 'El producto no existe.') unless product

      batch.add(product.id, quantity)
      @added_product = product
      @added_quantity = quantity

      # Turbo actualiza SÓLO el panel del lote y repone la cantidad de la fila
      # agregada. La sección de búsqueda no se toca: el término, sus resultados y
      # el scroll se quedan como estaban, que es como se trabaja en bodega
      # (varios SKU seguidos del mismo resultado de búsqueda).
      respond_to do |format|
        format.turbo_stream do
          load_batch_state
          @assignable = assignable_for(product)
          flash.now[:notice] = "#{quantity} × #{product.product_name} agregado al lote."
        end
        format.html do
          redirect_back_to_page(notice: "#{quantity} × #{product.product_name} agregado al lote.")
        end
      end
    rescue ArgumentError, TypeError
      retry_page(alert: 'La cantidad debe ser un número entero mayor a cero.')
    rescue Admin::LocationAssignmentBatch::TooManyLines
      retry_page(alert: "El lote admite hasta #{Admin::LocationAssignmentBatch::MAX_LINES} productos.")
    end

    # Editar, quitar y vaciar tocan SÓLO el lote. Ni la búsqueda ni el resumen de
    # la ubicación cambian: nada de esto ha llegado todavía a la base.
    def update_line
      batch.set_quantity(params[:product_id], params[:quantity])
      respond_with_batch
    end

    def remove_line
      batch.remove(params[:product_id])
      respond_with_batch(notice: 'Producto quitado del lote.')
    end

    # Vaciar el lote no cambia de estante: el operador sigue trabajando ahí, sólo
    # está descartando lo que llevaba juntado.
    def clear
      batch.clear_lines
      respond_with_batch(notice: 'Lote vaciado.')
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
      # Se vacían las líneas pero se conserva el estante: el operador sigue
      # parado delante del mismo, y así al volver ve el resumen ya actualizado
      # con lo que acaba de dejar ahí.
      batch.clear_lines
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

    # Cuánto queda asignable ahora mismo para reponer el input de cantidad.
    def assignable_for(product)
      Inventories::LocationAssignment.eligible_scope(product.id).count
    end

    # Estado mínimo para repintar el panel del lote.
    def load_batch_state
      @batch = batch
      @batch_lines = batch.detailed_lines
      @q = params[:q].to_s.strip
    end

    # Estado completo de la pantalla: hace falta cuando cambia la ubicación,
    # porque eso altera también los resultados y el resumen del estante.
    def load_page_state
      load_batch_state
      @location_options = assignable_location_options
      @location_inventory = Inventories::LocationInventorySummary.for(batch.location)
      @search_results = Inventories::UnlocatedOverview.new(term: @q).rows
    end

    # Hojas activas en UNA consulta: recorrer InventoryLocation.active llamando a
    # leaf? hace una consulta por ubicación.
    def assignable_location_options
      parent_ids = InventoryLocation.where.not(parent_id: nil).select(:parent_id)
      InventoryLocation.active.where.not(id: parent_ids).order(:path_cache, :name).map do |location|
        ["#{location.path_cache.presence || location.name} (#{location.code})", location.id]
      end
    end

    def respond_with_batch(notice: nil, alert: nil)
      respond_to do |format|
        format.turbo_stream do
          load_batch_state
          flash.now[:notice] = notice if notice
          flash.now[:alert] = alert if alert
          render :batch_update
        end
        format.html { redirect_back_to_page(notice: notice, alert: alert) }
      end
    end

    def respond_with_page(notice: nil, alert: nil)
      respond_to do |format|
        format.turbo_stream do
          load_page_state
          flash.now[:notice] = notice if notice
          flash.now[:alert] = alert if alert
          render :page_update
        end
        format.html { redirect_back_to_page(notice: notice, alert: alert) }
      end
    end

    def batch = @batch ||= Admin::LocationAssignmentBatch.new(session)

    def redirect_back_to_page(notice: nil, alert: nil, clear_search: false, extra: {})
      query = clear_search ? {} : { q: params[:q].presence }
      redirect_to admin_inventory_unlocated_path(**query.compact, **extra.compact),
                  notice: notice, alert: alert, status: :see_other
    end

    # Conserva lo que el operador tenía escrito para que sólo tenga que corregir
    # el dato que falló. Con Turbo ni siquiera hace falta reponerlo: no se
    # repinta nada, así que la cantidad tecleada sigue en su sitio. El fallback
    # HTML sí tiene que devolverlo por la URL.
    def retry_page(alert:)
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = alert
          render :flash_only
        end
        format.html do
          redirect_back_to_page(alert: alert,
                                extra: { retry_product_id: params[:product_id].presence,
                                         retry_quantity: params[:quantity].presence })
        end
      end
    end
  end
end
