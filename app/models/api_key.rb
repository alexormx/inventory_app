# frozen_string_literal: true

# Clave de API para una integración (KataFrame). El token en claro se devuelve
# una sola vez en .generate!; en la base solo queda su digest SHA-256 y un
# prefijo para reconocerla en el admin. Al ser un token aleatorio de alta
# entropía, SHA-256 basta (no hace falta bcrypt) y permite buscar por índice.
class ApiKey < ApplicationRecord
  SCOPES = %w[products:read products:write photos:write].freeze
  TOKEN_PREFIX = 'pk_'
  # Para no escribir en cada petición: last_used_at se refresca como mucho una vez por minuto
  LAST_USED_RESOLUTION = 1.minute

  belongs_to :created_by, class_name: 'User'

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true
  validate :scopes_are_known

  scope :active, -> { where(revoked_at: nil) }

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  # => [ApiKey, token en claro]
  def self.generate!(name:, scopes:, created_by:)
    token = "#{TOKEN_PREFIX}#{SecureRandom.base58(40)}"
    key = create!(name: name, scopes: scopes, created_by: created_by,
                  token_digest: digest(token), token_prefix: token.first(11))
    [key, token]
  end

  def self.authenticate(token)
    return nil unless token.is_a?(String) && token.start_with?(TOKEN_PREFIX)

    active.find_by(token_digest: digest(token))
  end

  def allows?(scope)
    scopes.include?(scope.to_s)
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current) unless revoked?
  end

  def touch_last_used!
    now = Time.current
    return if last_used_at && last_used_at > now - LAST_USED_RESOLUTION

    update_column(:last_used_at, now)
  end

  private

  def scopes_are_known
    list = Array(scopes)
    errors.add(:scopes, 'debe incluir al menos un permiso') if list.empty?
    unknown = list - SCOPES
    errors.add(:scopes, "desconocidos: #{unknown.join(', ')}") if unknown.any?
  end
end
