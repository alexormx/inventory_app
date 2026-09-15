# frozen_string_literal: true

module ShoppingCarts
  # Glue between a successful authentication and SessionReconciler: reads the
  # browser cart and session id from the request session, runs one
  # reconciliation, writes the canonical result back into session[:cart].
  #
  # A cart problem must never break sign-in, so every failure is logged and
  # swallowed here. Retrying later is always safe (see SessionReconciler).
  # Nothing secret is logged: no key, no digest, no payload, no cookie.
  class AuthenticationHandoff
    LOG_TAG = '[ShoppingCarts::AuthenticationHandoff]'
    # Written next to session[:cart] after every hydration; see
    # SessionReconciler "Session id renewal". Devise resets the whole session
    # on sign-out, which clears it.
    MARKER_KEY = :cart_reconciled

    def self.call(user:, session:)
      new(user: user, session: session).call
    end

    def initialize(user:, session:)
      @user = user
      @session = session
    end

    def call
      result = SessionReconciler.call(
        user: @user,
        session_cart: @session[:cart],
        session_id: session_public_id,
        reconciled_marker: @session[MARKER_KEY]
      )
      @session[:cart] = result.session_cart if result.hydrate?
      @session[MARKER_KEY] = result.session_marker if result.mark?
      log(result)
      result
    rescue StandardError => e
      Rails.logger.error("#{LOG_TAG} #{e.class} user_id=#{@user.id} - authentication continues")
      nil
    end

    private

    # ActionDispatch::Request::Session#id is only populated once the session
    # is loaded; reading a key above already did that.
    def session_public_id
      @session.respond_to?(:id) ? @session.id&.public_id : nil
    end

    def log(result)
      summary = "#{LOG_TAG} status=#{result.status} user_id=#{@user.id} cart_id=#{result.cart&.id} " \
                "receipt_id=#{result.receipt&.id} lines=#{result.session_cart&.values&.sum(&:size)}"
      details = result.details.except(:errors, :error)
      summary += " #{details.map { |k, v| "#{k}=#{v}" }.join(' ')}" if details.any?

      # :session_ahead is the expected outcome of a re-authentication after
      # storefront edits, not a problem worth a warning.
      if result.success? || result.status == :session_ahead
        Rails.logger.info(summary)
      else
        Rails.logger.warn(summary)
      end
    end
  end
end
