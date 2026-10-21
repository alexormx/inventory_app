# frozen_string_literal: true

module Admin
  # Claves de API para integraciones (KataFrame). El token en claro solo existe
  # en la respuesta de #create: se renderiza ahí mismo (sin redirect ni flash)
  # para que no quede en la sesión ni en una URL.
  class ApiKeysController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    SCOPE_LABELS = {
      'products:read' => 'Leer productos',
      'products:write' => 'Crear y editar productos',
      'photos:write' => 'Subir fotos'
    }.freeze
    helper_method :scope_label

    def index
      @api_keys = ApiKey.includes(:created_by).order(Arel.sql('revoked_at IS NOT NULL'), created_at: :desc)
    end

    def new
      @api_key = ApiKey.new(scopes: ApiKey::SCOPES)
    end

    def create
      @api_key, @token = ApiKey.generate!(name: api_key_params[:name],
                                          scopes: Array(api_key_params[:scopes]).compact_blank,
                                          created_by: current_user)
      render :created, status: :created
    rescue ActiveRecord::RecordInvalid => e
      @api_key = e.record
      render :new, status: :unprocessable_entity
    end

    def revoke
      ApiKey.find(params[:id]).revoke!
      redirect_to admin_api_keys_path, notice: 'Clave revocada: deja de funcionar de inmediato.'
    end

    private

    def api_key_params
      params.expect(api_key: [:name, { scopes: [] }])
    end

    def scope_label(scope)
      SCOPE_LABELS.fetch(scope, scope)
    end
  end
end
