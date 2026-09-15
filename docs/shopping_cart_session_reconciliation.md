# Shopping cart: session import and reconciliation (Phase B)

Phase B connects the legacy cookie cart (`session[:cart]`, see
`app/models/cart.rb`) with the persistent cart tables introduced by the
foundation PR (#174), **at the authentication boundary only**.

`session[:cart]` remains the live storefront source of truth. Add, update,
remove, the cart page and checkout keep reading and writing the session.
Persistent carts are written exactly once per browser session, when the
customer authenticates.

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

## Non-goals (Phase C and later)

Storefront cutover to `ShoppingCart`, continuous synchronization on every
mutation, checkout conversion from the persistent cart, persistent pricing /
discounts / taxes, inventory reservation changes, Customer 360 cart UI,
abandoned-cart features. No migration is introduced by Phase B.
