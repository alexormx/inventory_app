# frozen_string_literal: true

module ShoppingCarts
  # Builds the exact session[:cart] structure Cart.new(session) and the cart
  # controllers expect - { "product_id" => { "condition" => quantity } } -
  # from a persistent cart. Lines whose product no longer exists are left out:
  # Cart#build_items would skip them anyway, and re-adding the id would only
  # keep a ghost line in the cookie. Their rows are not touched.
  class SessionHydrator
    def self.call(cart)
      cart.shopping_cart_items
          .where.not(product_id: nil)
          .order(:product_reference, :condition)
          .pluck(:product_reference, :condition, :quantity)
          .each_with_object({}) do |(product_reference, condition, quantity), session_cart|
            condition_name = ShoppingCartItem.conditions.key(condition) || condition.to_s
            (session_cart[product_reference.to_s] ||= {})[condition_name] = quantity
          end
    end
  end
end
