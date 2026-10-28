# frozen_string_literal: true

# Un producto en la lista de deseos de un cliente. Quitarlo o comprarlo lo
# cierra (removed_at + removal_reason) en lugar de borrarlo, para que las
# estadísticas del admin sepan qué se guardó y luego se compró.
class Favorite < ApplicationRecord
  SOURCES = %w[heart abandoned_cart].freeze
  REMOVAL_REASONS = %w[removed purchased].freeze

  belongs_to :user
  belongs_to :product

  validates :source, inclusion: { in: SOURCES }
  validates :removal_reason, inclusion: { in: REMOVAL_REASONS }, allow_nil: true

  scope :open, -> { where(removed_at: nil) }

  # Abre el favorito si no está ya en la lista. Un producto que ya estaba
  # guardado conserva su origen: si el cliente lo guardó con el corazón, que
  # luego lo abandone en el carrito no lo vuelve "de carrito".
  # El savepoint deja que un doble clic simultáneo pierda la carrera sin
  # abortar la transacción de quien llama (p. ej. el vencimiento del carrito).
  def self.save_for(user, product, source: 'heart')
    transaction(requires_new: true) do
      open.find_or_create_by!(user: user, product: product) { |favorite| favorite.source = source }
    end
  rescue ActiveRecord::RecordNotUnique
    open.find_by!(user: user, product: product)
  end

  def self.mark_purchased(user_id:, product_id:, sale_order_id:)
    open.where(user_id: user_id, product_id: product_id)
        .update_all(removed_at: Time.current, removal_reason: 'purchased', sale_order_id: sale_order_id,
                    updated_at: Time.current)
  end

  def remove!
    update!(removed_at: Time.current, removal_reason: 'removed')
  end
end
