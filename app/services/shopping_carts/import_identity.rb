# frozen_string_literal: true

module ShoppingCarts
  # The stable identity of one browser session's import lifecycle.
  #
  # Derived from the Rails session id with a server-side key, not from a nonce
  # written during the login request: the cookie store persists session_id
  # inside the cookie on every write (ActionDispatch::Session::CookieStore
  # #persistent_session_id!), so any browser that holds a cart already holds
  # its session id. That is what makes a retry after "DB committed but the
  # response never reached the browser" find the same receipt - a nonce minted
  # during that same request would have died with it.
  #
  # Properties:
  # - unpredictable: 128-bit random session id, keyed through HMAC-SHA256 with
  #   a purpose-specific key from Rails.application.key_generator (the same
  #   derivation every Rails cookie/verifier key uses; secret_key_base itself
  #   is never used directly, nor exposed);
  # - stable across retries: the session id only changes when the session is
  #   reset, which Devise does on sign-out (Warden#logout -> reset_session!)
  #   and never on sign-in;
  # - naturally scoped: a different browser, or the same browser after
  #   logout, has a different session id and therefore a different key;
  # - only the SHA-256 digest of the key is ever persisted.
  class ImportIdentity
    KEY_SALT = 'shopping_carts/import_identity'
    KEY_BYTES = 32
    DIGEST_VERSION = 'v1'

    attr_reader :import_key

    def self.server_key
      Rails.application.key_generator.generate_key(KEY_SALT, KEY_BYTES)
    end

    def initialize(session_public_id)
      raise ArgumentError, 'session id is required' if session_public_id.blank?

      @import_key = OpenSSL::HMAC.hexdigest('SHA256', self.class.server_key, session_public_id.to_s)
    end

    def digest
      @digest ||= Digest::SHA256.hexdigest("#{DIGEST_VERSION}:#{@import_key}")
    end

    # Never leak the key through inspect/logging.
    def inspect
      "#<#{self.class.name} digest=#{digest.first(12)}…>"
    end
    alias to_s inspect
  end
end
