# frozen_string_literal: true

# Reconcile the legacy session cart with the user's persistent cart exactly
# once per authentication.
#
# Why a Warden hook and not a Devise controller override: every path that
# establishes a session - password sign-in (event :authentication),
# remember-me (:authentication), sign-in after a password reset
# (:set_user) - goes through Warden#set_user, and per-request session reads
# (:fetch) do not. A failed login never reaches set_user at all.
#
# Devise's own after_set_user hooks (activatable, ...) register when the User
# model loads, which under eager loading is AFTER initializers, so their
# order relative to this hook is not guaranteed: the active_for_authentication?
# check below is what keeps an unconfirmed or otherwise inactive account from
# importing anything.
Warden::Manager.after_set_user except: :fetch do |user, auth, opts|
  next unless opts[:scope] == :user && user.is_a?(User)
  next unless user.active_for_authentication?

  session = auth.env['rack.session']
  next if session.nil?

  ShoppingCarts::AuthenticationHandoff.call(user: user, session: session)
end
