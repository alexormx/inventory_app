# frozen_string_literal: true

module Admin
  class LocationTypesController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_location_type, only: %i[edit update destroy move]

    def index
      @location_types = LocationType.ordered
    end

    def new
      @location_type = LocationType.new
      @location_type.position = LocationType.maximum(:position).to_i + 1
      @location_type.color = 'secondary'
      @location_type.icon = 'bi-geo-alt'
    end

    def edit; end

    def create
      @location_type = LocationType.new(location_type_params)

      if @location_type.save
        redirect_to admin_location_types_path, notice: "Tipo '#{@location_type.name}' creado exitosamente."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @location_type.update(location_type_params)
        redirect_to admin_location_types_path, notice: "Tipo '#{@location_type.name}' actualizado."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @location_type.inventory_locations.exists?
        redirect_to admin_location_types_path, alert: "No se puede eliminar '#{@location_type.name}' porque tiene ubicaciones asignadas."
      else
        @location_type.destroy
        redirect_to admin_location_types_path, notice: "Tipo '#{@location_type.name}' eliminado."
      end
    end

    # PATCH /admin/location_types/:id/move
    def move
      direction = params[:direction]

      case direction
      when 'up'
        move_up
      when 'down'
        move_down
      end

      redirect_to admin_location_types_path
    end

    private

    def set_location_type
      @location_type = LocationType.find(params[:id])
    end

    def location_type_params
      params.expect(location_type: %i[name code icon color position active])
    end

    def move_up
      previous_type = LocationType.where(position: ...@location_type.position).order(position: :desc).first
      return unless previous_type

      swap_positions(@location_type, previous_type)
    end

    def move_down
      next_type = LocationType.where('position > ?', @location_type.position).order(position: :asc).first
      return unless next_type

      swap_positions(@location_type, next_type)
    end

    def swap_positions(type1, type2)
      LocationType.transaction do
        pos1 = type1.position
        pos2 = type2.position
        type1.update!(position: pos2)
        type2.update!(position: pos1)
      end
    end
  end
end
