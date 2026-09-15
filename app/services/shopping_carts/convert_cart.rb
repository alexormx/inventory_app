# frozen_string_literal: true

module ShoppingCarts
  # Closes the customer's ACTIVE cart as `converted` for a freshly created
  # SaleOrder, inside Checkout::CreateOrder's transaction, so the order and
  # the conversion commit together or roll back together.
  #
  # Two steps, because of lock order. Every cart writer (mutations, the login
  # import, this class) takes SELECT ... FOR UPDATE on the cart row first, and
  # inserting a cart line then takes an implicit FOR KEY SHARE on the
  # referenced product, which conflicts with the FOR UPDATE checkout takes on
  # products. Checkout therefore locks the cart BEFORE the products
  # (lock_and_verify!, at the start of its transaction) and closes it at the
  # end (close!); locking the cart last would form a cycle with a concurrent
  # add and PostgreSQL would abort one side.
  #
  # Under the lock the live lines are compared with the lines the order is
  # priced from: a mutation that landed between the checkout snapshot and the
  # lock (another tab, another device) makes the checkout fail cleanly
  # (CartChanged) instead of converting a cart the order does not describe.
  # Lines whose product was deleted are not part of either side - the
  # storefront never shows them - and stay on the historical row.
  class ConvertCart
    class CartChanged < StandardError; end

    def self.call(cart:, sale_order:, lines:)
      lock_and_verify!(cart: cart, user_id: sale_order.user_id, lines: lines)
      close!(cart, sale_order)
    end

    def self.lock_and_verify!(cart:, user_id:, lines:)
      cart.lock!
      raise CartChanged, 'cart is no longer active' unless cart.status == 'active'
      raise CartChanged, 'cart belongs to another user' unless cart.user_id == user_id

      live = cart.shopping_cart_items.where.not(product_id: nil)
                 .pluck(:product_reference, :condition, :quantity)
                 .map { |reference, condition, quantity| [reference, condition.to_s, quantity] }
      expected = lines.map { |reference, condition, quantity| [reference.to_i, condition.to_s, quantity.to_i] }
      raise CartChanged, 'cart contents changed during checkout' unless live.sort == expected.sort

      cart
    end

    # The cart row is still locked by the caller's transaction, nothing can
    # have changed since lock_and_verify!.
    def self.close!(cart, sale_order)
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
