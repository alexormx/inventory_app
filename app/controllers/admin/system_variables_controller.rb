# frozen_string_literal: true

module Admin
  class SystemVariablesController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin

    def index
      @variables = SystemVariable.order(:name)
      @new_variable = SystemVariable.new
    end

    def create
      @variable = SystemVariable.new(variable_params)
      if @variable.save
        redirect_to admin_system_variables_path, notice: 'Variable creada.'
      else
        @variables = SystemVariable.order(:name)
        @new_variable = @variable
        render :index, status: :unprocessable_entity
      end
    end

    def update
      @variable = SystemVariable.find(params[:id])
      if @variable.update(variable_params)
        redirect_to admin_system_variables_path, notice: 'Variable actualizada.'
      else
        @variables = SystemVariable.order(:name)
        @new_variable = SystemVariable.new
        render :index, status: :unprocessable_entity
      end
    end

    private

    def variable_params
      params.expect(system_variable: %i[name value description])
    end

    def require_admin
      return if current_user&.role == 'admin'

      redirect_to root_path, alert: 'No autorizado'
      
    end
  end
end
