# frozen_string_literal: true

module ShoppingCarts
  # Writes the browser-side projection of an authenticated customer's durable
  # cart: session[:cart] in the exact shape the legacy Cart PORO reads, plus
  # the reconciliation marker Phase B uses so a renewed session id never turns
  # the projection back into an import source.
  #
  # The session is never read as authority for an authenticated customer -
  # Storefront::Persistent builds its Cart from memory - so an oversized
  # projection simply becomes an empty one (with a matching marker) instead of
  # risking a CookieOverflow at response time.
  class SessionProjection
    def self.write(session, active_cart, session_cart = nil)
      session_cart ||= active_cart ? SessionHydrator.call(active_cart) : {}
      projected = SessionHydrator.fits_session?(session_cart) ? session_cart : {}

      session[:cart] = projected
      session[AuthenticationHandoff::MARKER_KEY] = {
        'cart_id' => active_cart&.id,
        'digest' => SessionCartNormalizer.call(projected).digest
      }
      projected
    end
  end
end
