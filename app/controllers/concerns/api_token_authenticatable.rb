# frozen_string_literal: true

# Autenticación de /api/v1. Acepta dos credenciales en `Authorization`
# (cualquier esquema: Bearer, bearer, Token — se toma la última palabra):
#
# - Clave de API (`pk_…`, ver ApiKey): permisos por scope; su creador debe
#   seguir siendo admin.
# - Token legado (`users.api_token` de un admin): todos los permisos, como
#   siempre, para el generador de PDF y los scripts existentes.
module ApiTokenAuthenticatable
  extend ActiveSupport::Concern

  private

  def authenticate_with_token!
    token = request.headers['Authorization'].to_s.split.last

    if token.to_s.start_with?(ApiKey::TOKEN_PREFIX)
      key = ApiKey.authenticate(token)
      if key&.created_by&.admin?
        key.touch_last_used!
        @current_api_key = key
        @current_user = key.created_by
        return
      end
    elsif token.present?
      user = User.find_by(api_token: token)
      if user&.admin?
        @current_user = user
        return
      end
    end

    render json: { error: 'Unauthorized' }, status: :unauthorized
  end

  def current_api_key
    @current_api_key
  end

  def legacy_token?
    @current_api_key.nil?
  end

  # El token legado tiene todos los permisos.
  def require_scope!(scope)
    return if legacy_token? || current_api_key.allows?(scope)

    render json: { error: "Forbidden: missing scope #{scope}" }, status: :forbidden
  end

  # Endpoints que todavía no tienen permisos definidos (órdenes, pagos,
  # usuarios): solo el token legado.
  def reject_api_keys!
    return if legacy_token?

    render json: { error: 'Forbidden: API keys cannot access this endpoint' }, status: :forbidden
  end
end
