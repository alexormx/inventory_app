# frozen_string_literal: true

module ShoppingCarts
  # Reconciles a browser's legacy session[:cart] with the authenticated user's
  # persistent ACTIVE ShoppingCart, exactly once per browser session.
  #
  # session[:cart] stays the live storefront source of truth: this service
  # only runs at the authentication boundary, and its output (Result#session_cart
  # plus Result#session_marker) is what the caller writes back into the session.
  #
  # Exactly-once design
  # -------------------
  # * ImportIdentity gives one browser session a stable key; only its digest
  #   is persisted, as CartSessionImport#import_key_digest (unique).
  # * The receipt is INSERTED FIRST inside the import transaction, before any
  #   item is touched, so a concurrent duplicate fails on the unique index
  #   having written nothing, and a crash mid-merge rolls the receipt back
  #   with the lines. Cart contents and receipt therefore commit together or
  #   not at all.
  # * A retry with the same key and the same payload digest finds the receipt
  #   and only rehydrates the session (:reused) - quantities are never applied
  #   twice, whether the retry comes from a double submit, another thread,
  #   another dyno, or a process that died between COMMIT and the response.
  # * The same key with a different payload digest is a state mismatch:
  #   nothing is written or reinterpreted (:payload_mismatch).
  # * A receipt whose cart belongs to another user is never reused
  #   (:foreign_receipt): no write, no hydration.
  #
  # Session id renewal
  # ------------------
  # Warden renews the Rails session id on every authentication (fixation
  # protection), keeping the data. The key derived from the id therefore
  # identifies "this login attempt and its retries with the same cookie" -
  # which is precisely the crash / lost-response / double-submit window.
  # Once a response with a reconciled cart reaches the browser, the session
  # also carries a marker (reconciled_marker: persistent cart id + digest of
  # the hydrated cart). A later authentication event in the same browser
  # session then never re-imports what was hydrated:
  #   * marker digest == current session digest -> nothing new: rehydrate;
  #   * marker digest != current session digest -> the session moved on after
  #     hydration (storefront edits); persistence is not updated in Phase B
  #     (:session_ahead) - continuous sync is Phase C's job;
  #   * marker cart belongs to another user -> refuse (:foreign_session).
  #
  # Concurrency
  # -----------
  # * one active cart per user: the partial unique index, via ActiveCartResolver;
  # * one import per key: the receipt's unique index;
  # * one writer per cart at a time: SELECT ... FOR UPDATE on the cart row,
  #   taken before the receipt insert and every item write. This is what makes
  #   two browsers of the same user (different keys) serialize instead of
  #   losing each other's update. Optimistic lock_version is left untouched
  #   for later storefront persistence.
  #
  # Quantities are combined, never clamped to the storefront's per-condition
  # purchase limits. Only the technical bound (100_000, a DB check) is
  # enforced, and exceeding it fails the entire reconciliation atomically.
  class SessionReconciler
    MAX_ATTEMPTS = 3
    MAX_QUANTITY = SessionCartNormalizer::MAX_QUANTITY

    SUCCESS_STATUSES = %i[imported reused rehydrated noop].freeze

    Result = Struct.new(:status, :cart, :receipt, :session_cart, :session_marker, :details, keyword_init: true) do
      def success?
        SUCCESS_STATUSES.include?(status)
      end

      # Only a result carrying a session cart may rewrite the session.
      def hydrate?
        !session_cart.nil?
      end
    end

    class QuantityOverflow < StandardError; end
    class StaleCart < StandardError; end

    def self.call(user:, session_cart:, session_id:, reconciled_marker: nil)
      new(user: user, session_cart: session_cart, session_id: session_id, reconciled_marker: reconciled_marker).call
    end

    def initialize(user:, session_cart:, session_id:, reconciled_marker: nil)
      @user = user
      @raw_session_cart = session_cart
      @session_id = session_id
      @marker = reconciled_marker
    end

    def call
      normalized = SessionCartNormalizer.call(@raw_session_cart)
      return result(:invalid_payload, details: { errors: normalized.errors }) unless normalized.valid?
      return reconcile_after_hydration(normalized) if marker_present?

      importable = importable_lines(normalized.lines)
      return reconcile_without_import(skipped: normalized.lines.size - importable.size) if importable.empty?
      return result(:missing_identity) if @session_id.blank?

      identity = ImportIdentity.new(@session_id)
      existing = CartSessionImport.find_by(import_key_digest: identity.digest)
      return classify_existing(existing, normalized) if existing

      import_with_retries(identity, normalized, importable)
    end

    private

    def marker_present?
      @marker.is_a?(Hash) && @marker['digest'].is_a?(String)
    end

    def reconcile_after_hydration(normalized)
      marker_cart = ShoppingCart.find_by(id: @marker['cart_id']) if @marker['cart_id']
      return result(:foreign_session) if marker_cart && marker_cart.user_id != @user.id

      return result(:session_ahead, cart: marker_cart) unless same_digest?(@marker['digest'], normalized.digest)

      hydrated(:rehydrated, ActiveCartResolver.find(@user))
    end

    # Case A (nothing anywhere) is a no-op; Case C (persistent cart, empty
    # browser) only restores the persistent contents into the session. Lines
    # whose product no longer exists count as absent, like the storefront
    # already treats them, and never justify creating an empty cart.
    def reconcile_without_import(skipped:)
      cart = ActiveCartResolver.find(@user)
      return result(:noop, details: { skipped_missing_products: skipped }) unless cart

      hydrated(:rehydrated, cart, details: { skipped_missing_products: skipped })
    end

    def import_with_retries(identity, normalized, importable)
      MAX_ATTEMPTS.times do
        return import!(identity, normalized, importable)
      rescue ActiveRecord::RecordNotUnique
        existing = CartSessionImport.find_by(import_key_digest: identity.digest)
        return classify_existing(existing, normalized) if existing
        # Otherwise the collision was the first-cart race: try again.
      rescue ActiveRecord::RecordInvalid => e
        # A concurrent import that already COMMITTED is seen by the receipt's
        # model-level uniqueness validation before the INSERT ever reaches the
        # unique index; that is the same "someone else won" outcome.
        raise unless e.record.is_a?(CartSessionImport) && e.record.errors.of_kind?(:import_key_digest, :taken)

        existing = CartSessionImport.find_by(import_key_digest: identity.digest)
        return classify_existing(existing, normalized) if existing
      rescue StaleCart, ActiveRecord::InvalidForeignKey
        importable = importable_lines(normalized.lines)
        return reconcile_without_import(skipped: normalized.lines.size - importable.size) if importable.empty?
      end

      result(:retry_exhausted)
    end

    def import!(identity, normalized, importable)
      ActiveRecord::Base.transaction do
        cart = ActiveCartResolver.find_or_create!(@user)
        cart.lock!
        # The row could have been closed by another writer between the lookup
        # and the lock; never write into a non-active or foreign cart.
        raise StaleCart unless cart.status == 'active' && cart.user_id == @user.id

        receipt = CartSessionImport.create!(
          shopping_cart: cart,
          import_key_digest: identity.digest,
          source_payload_digest: normalized.digest,
          source_payload: normalized.payload
        )

        merge_details = merge_lines!(cart, importable)
        cart.update!(last_activity_at: Time.current)

        hydrated(:imported, cart, receipt: receipt,
                                  details: merge_details.merge(skipped_missing_products: normalized.lines.size - importable.size))
      end
    rescue QuantityOverflow => e
      result(:quantity_overflow, details: { error: e.message })
    end

    def merge_lines!(cart, importable)
      existing = cart.shopping_cart_items.to_a.index_by { |item| [item.product_reference, item.condition] }
      created = 0
      combined = 0
      over_business_limit = 0

      importable.each do |line, product|
        item = existing[[line.product_reference, line.condition]]
        quantity = line.quantity + (item&.quantity || 0)
        if quantity > MAX_QUANTITY
          raise QuantityOverflow,
                "product #{line.product_reference}/#{line.condition} would reach #{quantity} (> #{MAX_QUANTITY})"
        end

        if item
          item.update!(quantity: quantity)
          combined += 1
        else
          cart.shopping_cart_items.create!(
            product: product,
            product_reference: product.id,
            condition: line.condition,
            quantity: quantity,
            product_name_snapshot: product.product_name
          )
          created += 1
        end
        over_business_limit += 1 if quantity > business_limit_for(line.condition)
      end

      { lines_created: created, lines_combined: combined, over_business_limit: over_business_limit }
    end

    # One query for every product referenced; a line whose product is gone is
    # dropped (not "resurrected"), mirroring Cart#build_items.
    def importable_lines(lines)
      return [] if lines.empty?

      products = Product.where(id: lines.map(&:product_reference).uniq).index_by(&:id)
      lines.filter_map do |line|
        product = products[line.product_reference]
        [line, product] if product
      end
    end

    def classify_existing(receipt, normalized)
      cart = receipt.shopping_cart
      return result(:foreign_receipt) unless cart.user_id == @user.id

      return result(:payload_mismatch, cart: cart, receipt: receipt) unless same_digest?(receipt.source_payload_digest, normalized.digest)

      # The import already happened: rehydrate from whatever is active now
      # (the receipt's cart, in Phase B) and touch nothing.
      hydrated(:reused, ActiveCartResolver.find(@user), receipt: receipt, cart: cart)
    end

    # Every successful result that rewrites the session also hands back the
    # marker for it, so the next authentication knows what was hydrated.
    def hydrated(status, active_cart, receipt: nil, cart: active_cart, details: {})
      session_cart = active_cart ? SessionHydrator.call(active_cart) : {}
      marker = { 'cart_id' => active_cart&.id, 'digest' => SessionCartNormalizer.call(session_cart).digest }
      result(status, cart: cart, receipt: receipt, session_cart: session_cart, session_marker: marker, details: details)
    end

    def same_digest?(expected, actual)
      ActiveSupport::SecurityUtils.secure_compare(expected.to_s, actual.to_s)
    end

    # Storefront purchase caps are surfaced, never enforced here.
    def business_limit_for(condition)
      condition == 'brand_new' ? Cart::MAX_NEW_ITEMS_PER_PRODUCT : Cart::MAX_COLLECTIBLE_ITEMS_PER_PIECE
    end

    def result(status, cart: nil, receipt: nil, session_cart: nil, session_marker: nil, details: {})
      Result.new(status: status, cart: cart, receipt: receipt, session_cart: session_cart,
                 session_marker: session_marker, details: details)
    end
  end
end
