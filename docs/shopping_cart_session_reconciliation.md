# Shopping cart: session import and reconciliation (Phase B)

Phase B connects the legacy cookie cart (`session[:cart]`, see
`app/models/cart.rb`) with the persistent cart tables introduced by the
foundation PR (#174), **at the authentication boundary only**.

Phase B alone kept `session[:cart]` as the storefront source of truth; with
Phase C (below) the ACTIVE `ShoppingCart` is the authority for an
authenticated customer and the session is only a projection. What this
section describes - the import of a browser cart exactly once per browser
session at authentication - is unchanged.

## Flow

```
anonymous browser ──session[:cart]──┐
                                    ├─ Warden after_set_user(:authentication)
authenticated user's ACTIVE cart ───┘        └─ ShoppingCarts::AuthenticationHandoff
                                                   └─ ShoppingCarts::SessionReconciler
                                                          ├─ SessionCartNormalizer   (canonical payload + SHA-256)
                                                          ├─ ImportIdentity          (stable per-browser key, digest only in DB)
                                                          ├─ ActiveCartResolver      (one ACTIVE cart per user)
                                                          └─ SessionHydrator         (persistent cart -> session[:cart])
```

Integration point: `config/initializers/shopping_cart_session_reconciliation.rb`.
Every path that establishes a session (password sign-in, remember-me,
sign-in after password reset) goes through `Warden#set_user` with
`event: :authentication`; per-request `:fetch` events and failed logins never
reach it. Any failure inside the handoff is logged and swallowed, so a cart
problem cannot break sign-in; retrying later is always safe.

## Reconciliation matrix

| persistent ACTIVE cart | browser cart | result | receipt | session rewritten |
|---|---|---|---|---|
| none | empty | `:noop` | no | no |
| none | lines | `:imported` – cart created, lines imported | yes | yes |
| exists | empty | `:rehydrated` – persistent contents restored | no | yes |
| exists | lines | `:imported` – merged | yes | yes |

Merge rules: same `product_reference` + `condition` → quantities are **added**;
different conditions of one product stay independent lines; disjoint lines
are preserved on both sides. Lines whose product no longer exists are
dropped, exactly as the storefront already ignores them; nothing is
"resurrected". Inactive products are kept, as the storefront still shows them.

Quantities are never clamped to the storefront purchase caps (3 new / 1
collectible); a combined quantity above the cap is persisted and surfaced in
the result details. Only the technical bound (100 000, a DB check constraint)
is enforced, and exceeding it fails the **entire** reconciliation atomically.

## Exactly-once guarantees

* **Import identity.** `ImportIdentity` derives the key from the Rails
  session id through HMAC-SHA256 with a purpose-specific key from
  `Rails.application.key_generator`. The cookie store persists the session id
  inside the cookie on every write, so a browser holding a cart already holds
  its identity **before** any import transaction commits. Only
  `SHA256("v1:" + key)` is stored (`cart_session_imports.import_key_digest`,
  unique). No nonce is minted during the login request.
* **Receipt-first transaction.** Inside one transaction: resolve/create the
  active cart → `SELECT ... FOR UPDATE` on the cart row → insert the receipt →
  merge lines → touch `last_activity_at`. Cart contents and receipt commit
  together or not at all.
* **Retry, same key, same payload digest** → `:reused`: nothing is applied
  again; the session is rehydrated from the current active cart.
* **Same key, different payload digest** → `:payload_mismatch`: history is
  never reinterpreted; no write, no hydration.
* **Receipt owned by another user** → `:foreign_receipt`: no write, no
  hydration.

### Session id renewal

Warden renews the session id on every authentication (fixation protection)
while keeping the data. The id-derived key therefore identifies *this login
attempt and its retries with the same cookie* — precisely the crash /
lost-response / double-submit window. After a hydrated response reaches the
browser, `session[:cart_reconciled]` (`cart_id` + digest of the hydrated
cart) tells the next authentication event what was already reconciled:

* marker digest == current browser cart digest → `:rehydrated` (no import);
* marker digest != current digest → `:session_ahead`: the customer edited the
  cart after hydration; persistence is **not** updated in Phase B (continuous
  sync is Phase C) and the session keeps every edit;
* marker cart owned by another user → `:foreign_session`: no write.

Devise resets the whole session on sign-out, which clears both the cart and
the marker.

## Crash safety

* Failure before COMMIT (any line, receipt creation, cart creation) → the
  transaction rolls back completely: no cart, no lines, no receipt.
* Process dies **after COMMIT, before the response/cookie** → the browser
  still holds the pre-login cookie (old session id, no marker). The retry
  derives the same key, finds the receipt, applies nothing, rehydrates.
  Covered by `spec/services/shopping_carts/session_reconciler_spec.rb`
  ("survives a crash after DB commit") and by a two-session request spec
  replaying the login with the stale cookie.

## Concurrency

Correctness comes from PostgreSQL, never from process-local state:

| race | arbiter |
|---|---|
| two first-cart creations | partial unique index `index_shopping_carts_on_user_id_when_active` (loser re-fetches the winner; INSERT runs in a savepoint) |
| two imports, same key | unique `import_key_digest` (loser finds the receipt → `:reused`); a winner that already committed surfaces through the model uniqueness validation and is handled identically |
| two browsers, same user | cart row lock (`FOR UPDATE`) serializes the merges; both receipts recorded, no lost update |
| overlapping item inserts | cart row lock + unique `(cart, product_reference, condition)` |

`lock_version` is untouched by Phase B and stays available for storefront
persistence.

## Security

* No plaintext key is persisted or logged; `ImportIdentity#inspect` hides it.
* Cross-user: receipts and markers are validated against
  `shopping_cart.user_id`; a mismatch is refused without writes.
* Session fixation protection is untouched (renewal still happens); nothing
  disables CSRF or cookie security.
* Malformed browser data (non-hash levels, unknown conditions, non-canonical
  ids, non-integer quantities, ambiguous duplicate keys) invalidates the whole
  payload; nothing is partially imported.
* Logs carry the result category, user id, cart id, receipt id and line
  counts only.

## Phase C: the persistent cart is the authenticated authority

Phase C removes the Phase B limitation ("edits after login are session-only").

| identity | authority | session[:cart] |
|---|---|---|
| visitor | `Cart` PORO on the session, unchanged | the cart |
| authenticated | the ACTIVE `ShoppingCart` | a projection of committed state, never read as authority |

`ShoppingCarts::Storefront.for(user:, session:)` (reached through
`ApplicationController#current_cart` / `storefront_cart`) is the single entry
point for controllers, helpers and views:

* **Reads.** `Storefront::Persistent#cart` builds the `Cart` PORO from an
  in-memory projection of the durable cart on every request, so the existing
  pricing, tax, shipping and view code work unchanged and a second device or
  tab sees committed state on its next request. The session receives the
  same projection (bounded by the cookie budget) plus the marker.
* **Writes.** `ShoppingCarts::ActiveCartMutation` — `add`, `set_quantity`,
  `remove`, `clear` — each in one transaction under `SELECT ... FOR UPDATE`
  on the cart row. The storefront's per-condition caps (`Cart.max_allowed_for`)
  are enforced under the lock (`:limit_exceeded` writes nothing). A line a
  login merge left above the cap is never clamped; the customer can lower or
  remove it. A cart that became terminal between lookup and lock is retried
  against a fresh active cart. Removing the last line keeps the cart ACTIVE
  and empty. A mutation that cannot commit is reported as a failure, never
  as success.
* **Unbound sessions.** If the session carries a browser cart but no marker
  (the login-time reconciliation failed, or the customer was already signed
  in when persistence shipped), the facade reconciles it late — idempotently,
  through the same `AuthenticationHandoff` — before projecting. If that fails
  the cookie is left untouched, so nothing is lost and the next request
  retries, while reads still come from durable state.
* **Checkout.** `CheckoutsController` prices and validates from the
  durable-backed `Cart` exactly as before; `Checkout::CreateOrder` receives
  the `ShoppingCart`, locks it **first** in its transaction (before the
  product locks - every cart writer is cart-first, and inserting a line takes
  a key-share lock on the product, so locking the cart last would deadlock
  against a concurrent add), verifies the live lines still equal the order
  snapshot, and closes it as `converted` with the `sale_order_id` at the end. Any mutation that landed in between (another tab) makes
  the checkout fail with a message and rolls the order back; a failed
  checkout of any kind leaves the cart ACTIVE with its contents. The next
  add after a conversion creates a fresh active cart; the converted one is
  never written again.
* **Marker.** `session[:cart_reconciled]` keeps its Phase B role — a bound
  session is never an import source — and is now also rewritten by every
  projection, so a renewed session id after re-authentication rehydrates
  instead of importing.

Still true after Phase C: no price, discount, tax or availability is stored
on cart rows; adding to the cart reserves no inventory; cart ids never come
from the browser; no migration.

## Non-goals (later)

Customer 360 cart UI, cart history, abandoned-cart features, viewed-product
tracking, real-time cross-device push.
