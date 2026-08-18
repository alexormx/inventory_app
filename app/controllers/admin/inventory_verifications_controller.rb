# frozen_string_literal: true

module Admin
  class InventoryVerificationsController < ApplicationController
    SERVICE = Inventories::VerifyPhysicalUnitService
    SEARCH_TYPES = {
      'inventory_id' => 'Inventory ID',
      'sku' => 'SKU',
      'product_name' => 'Nombre de producto',
      'purchase_order' => 'Orden de compra',
      'purchase_order_item' => 'Partida de compra',
      'sale_order' => 'Orden de venta',
      'sale_order_item' => 'Partida de venta'
    }.freeze
    DISPLAY_ASSOCIATIONS = %i[
      product
      inventory_location
      purchase_order
      purchase_order_item
      sale_order
      sale_order_item
    ].freeze
    PAGE_SIZE = 20
    # La selección se hace sobre una página (PAGE_SIZE), así que este tope sólo
    # entra en juego ante una petición armada a mano. Existe porque cada unidad
    # es una transacción propia y el dyno de producción tiene 512 MB: conviene
    # rechazar el lote entero antes que quedarse a medias.
    MAX_BULK_UNITS = 100

    before_action :authenticate_user!
    before_action :authorize_admin!

    def index
      @query = params[:q].to_s.strip
      @search_by = params[:search_by].presence_in(SEARCH_TYPES.keys) || 'inventory_id'
      @search_options = SEARCH_TYPES.invert.to_a
      @candidate_count = candidate_scope.count
      @inventories = searched_candidates
                     .includes(DISPLAY_ASSOCIATIONS)
                     .order(created_at: :asc, id: :asc)
                     .page(params[:page])
                     .per(PAGE_SIZE)
    end

    def show
      @inventory = inventory_scope.find(params[:id])

      if params[:event_id].present?
        load_verification_event
        render :success
        return
      end

      unless verification_candidate?(@inventory)
        redirect_to admin_inventory_verifications_path,
                    alert: non_candidate_alert_for(@inventory),
                    status: :see_other
        return
      end

      prepare_verification_form
    end

    # Paso 1 del flujo multi-unidad: el admin marcó casillas de unidades exactas
    # y pasa a revisarlas. No se escribe nada todavía; aquí sólo se cargan las
    # unidades y se congela el snapshot con el que se confirmará después.
    def bulk_review
      if requested_bulk_ids.size > MAX_BULK_UNITS
        redirect_to admin_inventory_verifications_path,
                    alert: "Selecciona como máximo #{MAX_BULK_UNITS} unidades por lote.",
                    status: :see_other
        return
      end

      @inventories = bulk_selected_inventories

      if @inventories.empty?
        redirect_to admin_inventory_verifications_path,
                    alert: 'Selecciona al menos una unidad de inventario para asignar ubicación.',
                    status: :see_other
        return
      end

      @expected_snapshots = @inventories.index_with { |inventory| SERVICE.snapshot_for(inventory) }
      @location_options = verification_location_options
      @skipped_ids = requested_bulk_ids - @inventories.map(&:id)
    end

    # Paso 2: confirmar. Cada unidad pasa por el servicio canónico de forma
    # independiente, con su propio snapshot y su propia transacción, para que una
    # unidad obsoleta no arrastre a las demás.
    def bulk
      location_id = params[:location_id].presence

      if requested_bulk_ids.empty?
        redirect_to admin_inventory_verifications_path,
                    alert: 'Selecciona al menos una unidad de inventario para asignar ubicación.',
                    status: :see_other
        return
      end

      if requested_bulk_ids.size > MAX_BULK_UNITS
        redirect_to admin_inventory_verifications_path,
                    alert: "Selecciona como máximo #{MAX_BULK_UNITS} unidades por lote.",
                    status: :see_other
        return
      end

      # Se cargan TODOS los IDs pedidos, no sólo los que siguen siendo
      # candidatos: quien decide si una unidad puede escribirse es el servicio,
      # y así cada unidad que el admin marcó recibe un resultado explícito en
      # lugar de desaparecer sin explicación.
      found = inventory_scope.where(id: requested_bulk_ids).index_by(&:id)

      @location = InventoryLocation.find_by(id: location_id)
      @results = requested_bulk_ids.map do |id|
        inventory = found[id]
        if inventory
          assign_single_unit(inventory, location_id)
        else
          { status: :failed, id: id, inventory: nil, reason: :not_found,
            message: "No existe inventario con ID #{id}.",
            next_action: 'Vuelve a la lista de unidades pendientes.' }
        end
      end
      @assigned = @results.select { |r| r[:status] == :assigned }
      @failures = @results.reject { |r| r[:status] == :assigned }

      render :bulk_result, status: (@failures.any? ? :unprocessable_entity : :ok)
    end

    def create
      attributes = verification_attributes
      result = verification_service.call(
        inventory_id: attributes[:inventory_id],
        result: attributes[:result],
        location_id: attributes[:location_id].presence,
        actor: current_user,
        expected_snapshot: attributes.fetch(:expected_snapshot, {}),
        notes: attributes[:notes]
      )

      redirect_to admin_inventory_verification_path(result.inventory, event_id: result.event.id),
                  notice: "Inventario ##{result.inventory.id} verificado correctamente.",
                  status: :see_other
    rescue SERVICE::StaleInventory => e
      render_conflict(e)
    rescue SERVICE::InvalidInventoryState => e
      render_non_retryable_error(e)
    rescue SERVICE::InvalidLocation,
           SERVICE::InvalidVerificationResult,
           SERVICE::InvalidSnapshot,
           SERVICE::ReservedInventoryRequiresReconciliation => e
      render_form_error(e)
    end

    private

    # El backlog muestra TODO lo que la app considera "en bodega sin ubicar"
    # (Inventory.requiring_location), para que cuadre con el contador del panel.
    # Poder verificarse es otra cosa: eso lo decide selectable_for_verification?.
    def candidate_scope
      Inventory.requiring_location.without_location
    end

    # Sólo se puede verificar físicamente lo que está físicamente en bodega.
    # 'pre_reserved' es una pieza que todavía viene EN TRÁNSITO y quedó apartada
    # (InventoryServices::ReserveSaleOrderItem la marca así sólo cuando
    # inventory.in_transit?, y al liberarla vuelve a in_transit). Nadie puede
    # tenerla en la mano para confirmar dónde está, así que se lista pero no se
    # selecciona; el servicio la rechaza igual si alguien fuerza la petición.
    def selectable_for_verification?(inventory)
      SERVICE::SUPPORTED_STATUSES.include?(inventory.status)
    end
    helper_method :selectable_for_verification?

    # IDs exactos marcados por el admin. Se normalizan a enteros y se deduplican;
    # cualquier cosa que no sea un ID se descarta en vez de ampliar la selección.
    def requested_bulk_ids
      @requested_bulk_ids ||= Array(params[:inventory_ids])
                              .flat_map { |value| value.to_s.split(',') }
                              .filter_map { |value| Integer(value.to_s.strip, 10, exception: false) }
                              .uniq
    end

    # Sólo se opera sobre unidades que siguen siendo candidatas. Filtrar por
    # candidate_scope impide que un ID manipulado alcance una pieza ya ubicada,
    # vendida o de otro estado no verificable.
    def bulk_selected_inventories
      return [] if requested_bulk_ids.empty?

      candidate_scope.includes(DISPLAY_ASSOCIATIONS)
                     .where(id: requested_bulk_ids)
                     .order(created_at: :asc, id: :asc)
                     .to_a
    end

    def assign_single_unit(inventory, location_id)
      snapshot = submitted_snapshot_for(inventory) || SERVICE.snapshot_for(inventory)
      result = SERVICE.call(
        inventory_id: inventory.id,
        result: 'found',
        location_id: location_id,
        actor: current_user,
        expected_snapshot: snapshot,
        notes: params[:notes]
      )
      { status: :assigned, id: inventory.id, inventory: result.inventory, event: result.event }
    rescue SERVICE::StaleInventory => e
      bulk_failure(inventory, :stale,
                   "Cambió después de cargarse (#{e.changed_fields.join(', ')}).",
                   'Vuelve a cargar la unidad y revisa su estado actual antes de reintentar.')
    rescue SERVICE::ReservedInventoryRequiresReconciliation => e
      bulk_failure(inventory, :reserved_reconciliation, e.message,
                   'Requiere conciliación a nivel de orden antes de tocar la pieza.')
    rescue SERVICE::InvalidInventoryState => e
      bulk_failure(inventory, :invalid_state, e.message,
                   'La unidad ya no es elegible para este flujo.')
    rescue SERVICE::InvalidLocation => e
      bulk_failure(inventory, :invalid_location, e.message,
                   'Elige una ubicación activa y final.')
    rescue SERVICE::InvalidSnapshot => e
      bulk_failure(inventory, :invalid_snapshot, e.message,
                   'Recarga la selección para capturar el estado actual.')
    end

    def bulk_failure(inventory, reason, message, next_action)
      { status: :failed, id: inventory.id, inventory: inventory, reason: reason,
        message: message, next_action: next_action }
    end

    # El snapshot se captura en la pantalla de revisión, no en la confirmación:
    # así una unidad que cambió entre ambos pasos falla como StaleInventory en
    # lugar de asignarse sobre un estado que el admin nunca vio.
    def submitted_snapshot_for(inventory)
      raw = params.dig(:expected_snapshots, inventory.id.to_s)
      return if raw.blank?

      permitted = raw.permit(*SERVICE::SNAPSHOT_FIELDS).to_h
      return if SERVICE::SNAPSHOT_FIELDS.any? { |field| !permitted.key?(field) }

      permitted
    end

    def verification_location_options
      verification_locations.map do |location|
        label = location.path_cache.presence || location.name
        ["#{label} (#{location.code})", location.id]
      end
    end

    def inventory_scope
      Inventory.includes(DISPLAY_ASSOCIATIONS)
    end

    def searched_candidates
      return candidate_scope if @query.blank?

      case @search_by
      when 'inventory_id'
        query_by_numeric_id(:id)
      when 'sku'
        query_product_field(:product_sku)
      when 'product_name'
        query_product_field(:product_name)
      when 'purchase_order'
        candidate_scope.where(purchase_order_id: order_identifier_variants)
      when 'purchase_order_item'
        query_by_numeric_id(:purchase_order_item_id)
      when 'sale_order'
        candidate_scope.where(sale_order_id: order_identifier_variants)
      when 'sale_order_item'
        query_by_numeric_id(:sale_order_item_id)
      else
        candidate_scope.none
      end
    end

    def query_product_field(field)
      escaped_query = ActiveRecord::Base.sanitize_sql_like(@query.downcase)
      scope = candidate_scope.joins(:product)

      case field
      when :product_sku
        scope.where('LOWER(products.product_sku) LIKE :query', query: "%#{escaped_query}%")
      when :product_name
        scope.where('LOWER(products.product_name) LIKE :query', query: "%#{escaped_query}%")
      else
        scope.none
      end
    end

    def query_by_numeric_id(field)
      identifier = Integer(@query, 10)
      candidate_scope.where(field => identifier)
    rescue ArgumentError
      candidate_scope.none
    end

    def order_identifier_variants
      [@query, @query.upcase].uniq
    end

    def verification_attributes
      @verification_attributes ||= params.expect(
        verification: [:inventory_id, :result, :location_id, :notes, { expected_snapshot: SERVICE::SNAPSHOT_FIELDS }]
      ).to_h.deep_symbolize_keys
    end

    def verification_service
      SERVICE
    end

    def non_candidate_alert_for(inventory)
      if inventory.pre_reserved?
        'Pre apartado: la pieza sigue en tránsito, así que todavía no puede verificarse físicamente.'
      else
        'La unidad ya no requiere verificación física individual.'
      end
    end

    def verification_candidate?(inventory)
      inventory.inventory_location_id.nil? && inventory.status.in?(SERVICE::SUPPORTED_STATUSES)
    end

    def prepare_verification_form
      @expected_snapshot = verification_service.snapshot_for(@inventory)
      @location_options = verification_location_options
    end

    def verification_locations
      parent_ids = InventoryLocation.where.not(parent_id: nil).select(:parent_id)
      InventoryLocation.active.where.not(id: parent_ids).order(:path_cache, :name)
    end

    def load_verification_event
      @event = InventoryEvent.where(
        inventory_id: @inventory.id,
        event_type: 'physical_inventory_verification'
      ).find(params[:event_id])
      @event_metadata = @event.metadata.stringify_keys
      location_ids = @event_metadata.values_at('previous_location_id', 'new_location_id').compact
      @event_locations = InventoryLocation.where(id: location_ids).index_by(&:id)
    end

    def submitted_inventory
      inventory_scope.find_by(id: verification_attributes[:inventory_id])
    end

    def render_conflict(error)
      @inventory = submitted_inventory
      @changed_fields = error.changed_fields
      @error_message = 'Esta unidad cambió después de cargar la página. Revisa el estado actual antes de intentarlo de nuevo.'
      render :conflict, status: :conflict
    end

    def render_non_retryable_error(error)
      @inventory = submitted_inventory
      @error_message = human_error_message(error)
      render :error, status: :unprocessable_entity
    end

    def render_form_error(error)
      @inventory = submitted_inventory
      unless @inventory && verification_candidate?(@inventory)
        render_non_retryable_error(error)
        return
      end

      @error_message = human_error_message(error)
      prepare_verification_form
      render :show, status: :unprocessable_entity
    end

    def human_error_message(error)
      case error
      when SERVICE::InvalidLocation
        "La ubicación no es válida: #{error.message}"
      when SERVICE::InvalidInventoryState
        'La unidad ya no es elegible para este flujo de verificación.'
      when SERVICE::InvalidSnapshot
        'No fue posible validar el estado cargado. Recarga la unidad antes de confirmar.'
      when SERVICE::InvalidVerificationResult
        'Selecciona un resultado de verificación permitido.'
      when SERVICE::ReservedInventoryRequiresReconciliation
        'El inventario reservado dañado o faltante requiere conciliación a nivel de orden.'
      else
        'No fue posible completar la verificación.'
      end
    end
  end
end
