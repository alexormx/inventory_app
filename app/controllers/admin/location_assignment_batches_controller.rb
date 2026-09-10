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
      discard_lines = ActiveModel::Type::Boolean.new.cast(params[:confirm_change])
      unless batch.change_location(params[:location_id], discard_lines: discard_lines)
        return respond_with_page(
          alert: "Ya tienes #{batch.total_units} pieza(s) preparadas para " \
                 "#{batch.location&.full_path}. Vacía el lote si quieres cambiar de ubicación."
        )
      end
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

      product = Product.find_by(id: params[:product_id])
      return retry_page(alert: 'El producto no existe.') unless product

      # El límite lo pone el inventario, no el formulario: la comprobación vive
      # en el modelo, dentro de una transacción con la fila bloqueada, porque dos
      # clics seguidos leen el mismo "quedan 2" y si no acaban metiendo 4.
      quantity = batch.add(product.id, params[:quantity])
      @added_product = product
      @added_quantity = quantity

      # Turbo actualiza SÓLO el panel del lote y repone la cantidad de la fila
      # agregada. La sección de búsqueda no se toca: el término, sus resultados y
      # el scroll se quedan como estaban, que es como se trabaja en bodega
      # (varios SKU seguidos del mismo resultado de búsqueda).
      respond_to do |format|
        format.turbo_stream do
          load_batch_state
          @added_row = search_row_for(product)
          flash.now[:notice] = "#{@added_quantity} × #{product.product_name} en el lote."
        end
        format.html do
          redirect_back_to_page(notice: "#{@added_quantity} × #{product.product_name} en el lote.")
        end
      end
    rescue ArgumentError, TypeError
      retry_page(alert: 'La cantidad debe ser un número entero mayor a cero.')
    rescue Admin::LocationAssignmentBatch::ExceedsAvailable => e
      retry_page(alert: e.message)
    end

    # "Agregar todas las disponibles": la cantidad la calcula el servidor al
    # momento. Si el navegador mandara un número, dos pestañas con datos viejos
    # se pasarían del inventario.
    def add_all
      return retry_page(alert: 'Selecciona primero la ubicación destino.') if batch.location_id.blank?

      product = Product.find_by(id: params[:product_id])
      return retry_page(alert: 'El producto no existe.') unless product

      added = batch.add_all(product.id)
      return retry_page(alert: "#{product.product_name}: ya tienes en el lote todo el inventario que se puede ubicar.") if added.zero?

      @added_product = product
      @added_quantity = batch.pending_for(product.id)
      respond_to do |format|
        format.turbo_stream do
          load_batch_state
          @added_row = search_row_for(product)
          flash.now[:notice] = "#{added} × #{product.product_name} agregado al lote."
          render :add_line
        end
        format.html { redirect_back_to_page(notice: "#{added} × #{product.product_name} agregado al lote.") }
      end
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
      # Se arrastra el término para que "Regresar" devuelva al operador justo
      # donde estaba, con su búsqueda hecha, y no a una pantalla en blanco.
      @q = params[:q].to_s.strip
    end

    # Asignación directa de TODO el lote, desde la misma pantalla de trabajo.
    #
    # Ya no se pasa por una página de revisión: el operador tiene el lote y el
    # resumen del estante delante mientras trabaja, así que mandarlo a otra
    # pantalla a leer lo mismo sobraba.
    #
    # El borrador queda bloqueado durante la transacción del servicio y sus
    # líneas se borran sólo después de una asignación exitosa. Por eso un segundo
    # envío —doble clic, dos pestañas— encuentra el borrador vacío, mientras que
    # un fallo conserva el lote entero para que el operador pueda reintentarlo.
    def assign_all
      if batch.empty?
        return respond_with_batch(alert: 'El lote ya se había asignado.') if batch.draft.just_assigned?

        return respond_with_batch(alert: 'Agrega al menos un producto antes de asignar.')
      end
      return respond_with_batch(alert: 'Selecciona la ubicación destino.') if batch.location.blank?

      location = batch.location
      result = nil
      taken = nil

      ActiveRecord::Base.transaction do
        taken = batch.consume! do |locked_lines|
          result = Inventories::BulkAssignLocationBatchService.call(
            lines: locked_lines, location_id: location.id, actor: current_user
          )
        end
      end

      return respond_with_batch(alert: 'El lote ya se había asignado.') if taken.blank?

      detail = result.lines.map { |l| "#{l[:inventories].size} #{l[:product].product_name}" }.join(', ')
      respond_with_assignment(
        notice: "#{result.assigned_count} unidades fueron asignadas a #{location.full_path}: #{detail}."
      )
    rescue Inventories::BulkAssignLocationBatchService::InsufficientEligibleInventory,
           Inventories::BulkAssignLocationBatchService::Error,
           Inventories::LocationAssignment::InvalidLocation => e
      # Todo o nada: la transacción se deshizo, así que el borrador sigue entero
      # y el resumen del estante no se movió. Sólo aparece el aviso.
      respond_with_batch(alert: e.message)
    end

    # Se conserva la ruta de revisión por compatibilidad, pero ya no forma parte
    # del camino normal: el panel del lote asigna directo.
    def confirm
      assign_all
    end

    private

    # La fila del producto tal y como la pinta la búsqueda, para poder repintar
    # sólo esa fila tras agregar. Se reusa el mismo overview que arma la lista,
    # así los números salen del mismo sitio y no pueden divergir.
    def search_row_for(product)
      Inventories::UnlocatedOverview.new(term: product.product_sku.to_s).rows
                                    .find { |row| row[:product].id == product.id } ||
        { product: product, assignable: 0, available: 0, reserved: 0, in_transit: 0 }
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
      overview = Inventories::UnlocatedOverview.new(term: @q)
      @total_assignable = overview.total_assignable
      @total_in_transit = overview.total_in_transit
      @total_products = overview.total_products
      @search_results = overview.rows
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

    # Éxito de la asignación: cambian cuatro cosas a la vez y ninguna más.
    # El estante ya tiene la mercancía (resumen), el lote quedó vacío, y lo que
    # sigue siendo asignable en los resultados y en los totales bajó. La búsqueda
    # y la ubicación elegida se quedan como estaban.
    def respond_with_assignment(notice:)
      respond_to do |format|
        format.turbo_stream do
          load_page_state
          flash.now[:notice] = notice
          render :assignment_done
        end
        format.html { redirect_back_to_page(notice: notice) }
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

    def batch = @batch ||= Admin::LocationAssignmentBatch.for(current_user)

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
