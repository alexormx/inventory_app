# frozen_string_literal: true

module ShoppingCarts
  # The single write path for an authenticated customer's ACTIVE cart:
  # add / set_quantity / remove / clear, each one transactional under
  # SELECT ... FOR UPDATE on the cart row, so concurrent tabs, devices and a
  # checkout in flight serialize on the database instead of on cookies.
  #
  # Business rules are the storefront's current ones (Cart.max_allowed_for):
  # an add or a set that would exceed the per-condition cap is refused
  # (:limit_exceeded) without writing. Lines that already sit above the cap
  # (a login merge never clamps) are left as they are until the customer
  # lowers or removes them - nothing is silently destroyed.
  #
  # Removing the last line keeps the cart ACTIVE and empty: `cleared` is a
  # terminal status meant for lifecycle bookkeeping, and a new add would only
  # have to create another cart.
  #
  # No pricing, no inventory: the cart is intent, not allocation.
  class ActiveCartMutation
    MAX_ATTEMPTS = 3

    Result = Struct.new(:status, :cart, :quantity, :session_cart, keyword_init: true) do
      def ok?
        status == :ok
      end
    end

    class StaleCart < StandardError; end
    class LimitExceeded < StandardError; end

    def self.add(user:, product:, condition:, quantity: 1)
      new(user).mutate(create_cart: true) do |cart, items|
        item = items[[product.id, condition]]
        new_quantity = (item&.quantity || 0) + quantity
        raise LimitExceeded if new_quantity > Cart.max_allowed_for(condition)

        upsert(cart, item, product, condition, new_quantity)
      end
    end

    def self.set_quantity(user:, product:, condition:, quantity:)
      return remove(user: user, product: product, condition: condition) if quantity <= 0

      new(user).mutate(create_cart: true) do |cart, items|
        raise LimitExceeded if quantity > Cart.max_allowed_for(condition)

        upsert(cart, items[[product.id, condition]], product, condition, quantity)
      end
    end

    # condition: nil removes every condition of the product, like Cart#remove.
    def self.remove(user:, product:, condition: nil)
      new(user).mutate(create_cart: false) do |cart, _items|
        scope = cart.shopping_cart_items.where(product_reference: product.id)
        scope = scope.where(condition: condition) if condition
        scope.delete_all
        0
      end
    end

    def self.clear(user:)
      new(user).mutate(create_cart: false) do |cart, _items|
        cart.shopping_cart_items.delete_all
        0
      end
    end

    def self.upsert(cart, item, product, condition, quantity)
      if item
        item.update!(quantity: quantity)
      else
        cart.shopping_cart_items.create!(
          product: product,
          product_reference: product.id,
          condition: condition,
          quantity: quantity,
          product_name_snapshot: product.product_name
        )
      end
      quantity
    end

    def initialize(user)
      @user = user
    end

    # Yields the locked ACTIVE cart and its lines indexed by
    # [product_reference, condition]; the block returns the resulting line
    # quantity. A unique-index loss on first-cart creation or a cart that
    # stopped being active between lookup and lock is retried from scratch.
    def mutate(create_cart:, &block)
      MAX_ATTEMPTS.times do
        return locked_mutation(create_cart, &block)
      rescue ActiveRecord::RecordNotUnique, StaleCart
        next
      rescue LimitExceeded
        return Result.new(status: :limit_exceeded)
      end

      Rails.logger.warn("[ShoppingCarts::ActiveCartMutation] retry_exhausted user_id=#{@user.id}")
      Result.new(status: :retry_exhausted)
    end

    private

    def locked_mutation(create_cart)
      ActiveRecord::Base.transaction do
        cart = create_cart ? ActiveCartResolver.find_or_create!(@user) : ActiveCartResolver.find(@user)
        # Removing from / clearing a cart that does not exist is already done.
        return Result.new(status: :ok, cart: nil, quantity: 0, session_cart: {}) unless cart

        cart.lock!
        raise StaleCart unless cart.status == 'active' && cart.user_id == @user.id

        items = cart.shopping_cart_items.to_a.index_by { |item| [item.product_reference, item.condition] }
        quantity = yield(cart, items)
        cart.update!(last_activity_at: Time.current)

        Result.new(status: :ok, cart: cart, quantity: quantity, session_cart: SessionHydrator.call(cart))
      end
    end
  end
end
