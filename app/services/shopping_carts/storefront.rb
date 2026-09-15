# frozen_string_literal: true

module ShoppingCarts
  # One cart facade for the storefront controllers and views, whatever the
  # customer's identity:
  #
  #   anonymous      -> Storefront::Anonymous  : the legacy session cart, as is
  #   authenticated  -> Storefront::Persistent : the durable ACTIVE ShoppingCart
  #
  # Both expose the same surface: #cart (a Cart PORO the existing views,
  # pricing, tax and shipping logic already understand), the mutation verbs
  # (#add / #set_quantity / #remove, answering :ok or :limit_exceeded with the
  # storefront's current caps) and #persistent_cart (nil when anonymous).
  #
  # For an authenticated customer the Cart PORO is built from an in-memory
  # projection of the durable cart on every request, so a second device or a
  # second tab sees committed state on its next request, and every mutation
  # commits durably before the session projection is rewritten.
  class Storefront
    def self.for(user:, session:)
      user ? Persistent.new(user, session) : Anonymous.new(session)
    end

    class Anonymous
      def initialize(session)
        @session = session
      end

      def cart
        @cart ||= Cart.new(@session)
      end

      def persistent_cart
        nil
      end

      def add(product, condition, quantity: 1)
        return :limit_exceeded unless cart.can_add?(product.id, condition: condition, quantity: quantity)

        cart.add_product(product.id, quantity, condition: condition)
        :ok
      end

      def set_quantity(product, condition, quantity)
        return :limit_exceeded if quantity > cart.max_allowed(condition)

        cart.update(product.id, quantity, condition: condition)
        :ok
      end

      def remove(product, condition: nil)
        cart.remove(product.id, condition: condition)
        :ok
      end
    end

    class Persistent
      def initialize(user, session)
        @user = user
        @session = session
      end

      # Built from the durable cart, never from the cookie; the cookie only
      # receives a projection of what was read - and only once the session is
      # bound to the durable cart (Phase B marker present). A session that
      # still carries an unreconciled browser cart (the login-time
      # reconciliation failed, or the customer was already signed in when
      # persistence shipped) is reconciled here first; if that fails too, the
      # cookie is left untouched so nothing is lost and the next request
      # retries, while the customer still sees durable state.
      def cart
        @cart ||= begin
          bind_session!
          Cart.new({ cart: projection.deep_dup })
        end
      end

      def persistent_cart
        return @persistent_cart if defined?(@persistent_cart)

        @persistent_cart = ActiveCartResolver.find(@user)
      end

      def add(product, condition, quantity: 1)
        apply(ActiveCartMutation.add(user: @user, product: product, condition: condition, quantity: quantity))
      end

      def set_quantity(product, condition, quantity)
        apply(ActiveCartMutation.set_quantity(user: @user, product: product, condition: condition, quantity: quantity))
      end

      def remove(product, condition: nil)
        apply(ActiveCartMutation.remove(user: @user, product: product, condition: condition))
      end

      private

      def projection
        @projection ||= persistent_cart ? SessionHydrator.call(persistent_cart) : {}
      end

      def session_bound?
        @session[AuthenticationHandoff::MARKER_KEY].is_a?(Hash)
      end

      def bind_session!
        return SessionProjection.write(@session, persistent_cart, projection) if session_bound?
        return SessionProjection.write(@session, persistent_cart, projection) if @session[:cart].blank?

        result = AuthenticationHandoff.call(user: @user, session: @session)
        return unless result&.mark?

        # Reconciled now: read the durable cart again, it may just have changed.
        remove_instance_variable(:@persistent_cart) if defined?(@persistent_cart)
        @projection = nil
      end

      # The mutation committed: project exactly what the database now holds.
      def apply(result)
        return result.status unless result.ok?

        @persistent_cart = result.cart
        @projection = result.session_cart
        @cart = nil
        SessionProjection.write(@session, result.cart, result.session_cart)
        :ok
      end
    end
  end
end
