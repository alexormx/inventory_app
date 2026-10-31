# frozen_string_literal: true

module Users
  # "Eliminar mi cuenta" de un cliente. El usuario no se borra: sus pedidos
  # (con su propia copia de la dirección en order_shipping_addresses) se
  # conservan para la contabilidad, pero la cuenta se queda sin datos
  # personales y sin forma de volver a iniciar sesión.
  class AnonymizeAccount
    class NotAllowed < StandardError; end

    def self.call(user)
      raise NotAllowed, 'Un administrador no puede eliminar su cuenta desde la tienda' if user.admin?

      ActiveRecord::Base.transaction do
        close_active_carts(user)
        NewsletterSubscriber.where('LOWER(email) = ?', user.email.to_s.downcase).delete_all
        user.shipping_addresses.destroy_all
        user.favorites.delete_all
        user.reviews.destroy_all
        user.comments.destroy_all
        # update_columns: sin reconfirmación ni correos de "tu email/contraseña cambió".
        user.update_columns(
          name: 'Cliente eliminado',
          email: "eliminado-#{user.id}-#{SecureRandom.hex(4)}@#{User::ANONYMIZED_EMAIL_DOMAIN}",
          encrypted_password: Devise::Encryptor.digest(User, SecureRandom.hex(32)),
          phone: nil, address: nil, tax_id: nil, notes: nil, api_token: nil,
          unconfirmed_email: nil, confirmation_token: nil, reset_password_token: nil,
          reset_password_sent_at: nil, remember_created_at: nil, cookies_accepted: nil,
          updated_at: Time.current
        )
      end
      user
    end

    # Libera los apartados igual que ShoppingCarts::ExpireCart, sin pasar sus
    # productos a favoritos.
    def self.close_active_carts(user)
      user.shopping_carts.where(status: 'active').find_each do |cart|
        cart.lock!
        CartInventoryHold.for_cart(cart).delete_all
        cart.update!(status: 'cleared', closed_at: Time.current, anonymous_token_digest: nil)
      end
    end
    private_class_method :close_active_carts
  end
end
