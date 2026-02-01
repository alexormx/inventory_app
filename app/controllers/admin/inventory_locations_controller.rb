# frozen_string_literal: true

module Admin
  class InventoryLocationsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_inventory_location, only: %i[show edit update destroy children]

    def index
      @locations = InventoryLocation.roots.ordered.includes(:children)
      @tree = InventoryLocation.tree
      @location_types = LocationType.options_for_select
    end

    def show
      @children = @inventory_location.children.ordered
      @inventories_count = Inventory.where(inventory_location_id: [@inventory_location.id] + @inventory_location.descendants.map(&:id)).count
    end

    def new
      @inventory_location = InventoryLocation.new
      @inventory_location.parent_id = params[:parent_id] if params[:parent_id].present?
      @inventory_location.location_type = suggested_type_for_parent
      set_form_data
    end

    def edit
      set_form_data
    end

    def create
      @inventory_location = InventoryLocation.new(inventory_location_params)

      if @inventory_location.save
        respond_to do |format|
          format.html { redirect_to admin_inventory_locations_path, notice: "Ubicación '#{@inventory_location.name}' creada exitosamente." }
          format.turbo_stream { redirect_to admin_inventory_locations_path, notice: "Ubicación '#{@inventory_location.name}' creada exitosamente." }
          format.json { render json: { status: 'ok', id: @inventory_location.id, location: location_json(@inventory_location) }, status: :created }
        end
      else
        set_form_data
        respond_to do |format|
          format.html { render :new, status: :unprocessable_entity }
          format.turbo_stream { render :new, status: :unprocessable_entity }
          format.json { render json: { status: 'error', errors: @inventory_location.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def update
      if @inventory_location.update(inventory_location_params)
        respond_to do |format|
          format.html { redirect_to admin_inventory_locations_path, notice: "Ubicación '#{@inventory_location.name}' actualizada." }
          format.turbo_stream { redirect_to admin_inventory_locations_path, notice: "Ubicación '#{@inventory_location.name}' actualizada." }
          format.json { render json: { status: 'ok', location: location_json(@inventory_location) } }
        end
      else
        set_form_data
        respond_to do |format|
          format.html { render :edit, status: :unprocessable_entity }
          format.turbo_stream { render :edit, status: :unprocessable_entity }
          format.json { render json: { status: 'error', errors: @inventory_location.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def destroy
      if @inventory_location.has_children?
        respond_to do |format|
          format.html { redirect_to admin_inventory_locations_path, alert: 'No se puede eliminar una ubicación con sub-ubicaciones. Elimina primero los hijos.' }
          format.json { render json: { status: 'error', message: 'Cannot delete location with children' }, status: :unprocessable_entity }
        end
      elsif Inventory.where(inventory_location_id: @inventory_location.id).exists?
        respond_to do |format|
          format.html { redirect_to admin_inventory_locations_path, alert: 'No se puede eliminar una ubicación con inventario asignado.' }
          format.json { render json: { status: 'error', message: 'Cannot delete location with assigned inventory' }, status: :unprocessable_entity }
        end
      else
        @inventory_location.destroy
        respond_to do |format|
          format.html { redirect_to admin_inventory_locations_path, notice: "Ubicación '#{@inventory_location.name}' eliminada." }
          format.json { render json: { status: 'ok' } }
        end
      end
    end

    # GET /admin/inventory_locations/:id/children - Returns children for AJAX tree expansion
    def children
      @children = @inventory_location.children.ordered
      respond_to do |format|
        format.json { render json: @children.map { |c| location_json(c) } }
        format.html { render partial: 'location_children', locals: { children: @children, depth: params[:depth].to_i } }
      end
    end

    # GET /admin/inventory_locations/tree - Returns full tree as JSON for JS components
    def tree
      @tree = InventoryLocation.tree
      render json: @tree
    end

    # GET /admin/inventory_locations/options - Returns flat options for select dropdowns
    def options
      @options = InventoryLocation.nested_options
      respond_to do |format|
        format.json { render json: @options.map { |label, id| { id: id, label: label } } }
        format.html { render partial: 'location_options', locals: { options: @options } }
      end
    end

    # GET /admin/inventory_locations/search?q= - Search by code or name for autocomplete
    def search
      q = params[:q].to_s.strip.downcase
      if q.length < 2
        render json: []
        return
      end

      locations = InventoryLocation.active
                                   .where('LOWER(code) LIKE :q OR LOWER(name) LIKE :q', q: "%#{q}%")
                                   .order(:depth, :name)
                                   .limit(15)

      render json: locations.map { |loc|
        {
          id: loc.id,
          code: loc.code,
          name: loc.name,
          full_path: loc.full_path,
          location_type: loc.location_type,
          type_name: loc.type_name,
          depth: loc.depth
        }
      }
    end

    private

    def set_inventory_location
      @inventory_location = InventoryLocation.find(params[:id])
    end

    def inventory_location_params
      params.require(:inventory_location).permit(:name, :code, :location_type, :description, :parent_id, :position, :active)
    end

    def set_form_data
      @parent_options = InventoryLocation.nested_options
      @location_types = LocationType.options_for_select
    end

    def suggested_type_for_parent
      return 'warehouse' unless params[:parent_id].present?

      parent = InventoryLocation.find_by(id: params[:parent_id])
      return 'warehouse' unless parent

      parent.suggested_child_types.first || 'position'
    end

    def location_json(location)
      {
        id: location.id,
        name: location.name,
        code: location.code,
        type: location.location_type,
        type_name: location.type_name,
        full_path: location.full_path,
        depth: location.depth,
        active: location.active,
        has_children: location.has_children?,
        children_count: location.children.count
      }
    end
  end
end
