# frozen_string_literal: true

# Reconcile the legacy session cart with the user's persistent cart exactly
# once per authentication.
#
# Why a Warden hook and not a Devise controller override: every path that
# establishes a session - password sign-in, remember-me cookie, sign-in after
# password reset - goes through Warden#set_user with event :authentication,
# and none of them is a random anonymous request or a per-request :fetch.
# Registered after Devise's own hooks (activatable, lockable, ...), so an
# inactive or unconfirmed account is thrown out before this ever runs.
#
# A failed login never reaches set_user, so it never imports.
Warden::Manager.after_set_user except: :fetch do |user, auth, opts|
  next unless opts[:event] == :authentication
  next unless opts[:scope] == :user && user.is_a?(User)

  session = auth.env['rack.session']
  next if session.nil?

  ShoppingCarts::AuthenticationHandoff.call(user: user, session: session)
end
