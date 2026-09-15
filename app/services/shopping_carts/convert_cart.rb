# frozen_string_literal: true

module ShoppingCarts
  # Closes the customer's ACTIVE cart as `converted` for a freshly created
  # SaleOrder. Runs INSIDE Checkout::CreateOrder's transaction, so the order
  # and the conversion commit together or roll back together.
  #
  # The cart row is locked and its live lines compared with the lines the
  # order was built from: a mutation that landed between the checkout
  # snapshot and this point (another tab, another device) makes the checkout
  # fail cleanly (CartChanged) rather than converting a cart the order does
  # not describe. Lines whose product was deleted are not part of either
  # side - the storefront never shows them - and stay on the historical row.
  class ConvertCart
    class CartChanged < StandardError; end

    def self.call(cart:, sale_order:, lines:)
      cart.lock!
      raise CartChanged, 'cart is no longer active' unless cart.status == 'active'
      raise CartChanged, 'cart belongs to another user' unless cart.user_id == sale_order.user_id

      live = cart.shopping_cart_items.where.not(product_id: nil)
                 .pluck(:product_reference, :condition, :quantity)
                 .map { |reference, condition, quantity| [reference, condition.to_s, quantity] }
      expected = lines.map { |reference, condition, quantity| [reference.to_i, condition.to_s, quantity.to_i] }
      raise CartChanged, 'cart contents changed during checkout' unless live.sort == expected.sort

      now = Time.current
      cart.update!(
        status: 'converted',
        sale_order_id: sale_order.id,
        converted_at: now,
        closed_at: now,
        anonymous_token_digest: nil
      )
      cart
    end
  end
end
