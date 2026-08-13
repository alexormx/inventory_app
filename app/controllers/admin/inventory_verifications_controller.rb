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
                    alert: 'La unidad ya no requiere verificación física individual.',
                    status: :see_other
        return
      end

      prepare_verification_form
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

    def candidate_scope
      Inventory.requiring_location.without_location.where(status: %i[available reserved])
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

    def verification_candidate?(inventory)
      inventory.inventory_location_id.nil? && inventory.status.in?(%w[available reserved])
    end

    def prepare_verification_form
      @expected_snapshot = verification_service.snapshot_for(@inventory)
      @location_options = verification_locations.map do |location|
        label = location.path_cache.presence || location.name
        ["#{label} (#{location.code})", location.id]
      end
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
