# Cart expiry (4 h idle) and order alerts — design

Date: 2026-10-11
Status: approved in conversation, pending written-spec review
Source: purchase-flow audit of 2026-10-11 (findings 1, 2, 4, 6)

## Why

The audit found: unpaid sale orders retain 341 units (30 orders, 28 older than
90 days, several with partial payments — layaway, not abandonment), 39
imported orders with payments above their total ($28,582), one Pending order
with units already marked sold, checkout notes that crash checkout above
~2,000 characters (CookieOverflow), and a dead $99 shipping estimate in
`Cart`. The owner's decisions:

- **Only shopping carts expire**, 4 hours after the last change. Sale orders
  are **never** cancelled automatically.
- Unpaid orders older than **30 days**, overpaid orders and inconsistent
  orders are **reported in the admin panel** for manual treatment; nothing is
  changed automatically.

**Success:** a cart untouched for 4 h is emptied, its held units released, and
the customer is told why; the admin sees an "Alertas de órdenes" page and a
dashboard alert; checkout notes can no longer break checkout; the cart shows
"Envío desde $X".

## Decisions

| Question | Decision |
|---|---|
| Expiry anchor | 4 h after the last change (add / quantity / remove); viewing does not renew |
| Who expires | Authenticated durable carts and visitor session carts |
| Customer notice | Empty cart + "Tu carrito venció tras 4 horas sin actividad y liberamos las piezas apartadas." |
| Sale orders | Never auto-cancelled or modified |
| Pending alert threshold | Pending > **30 days** |
| Alert channel | Admin panel page + dashboard alert (no email) |
| Checkout notes | Stored on the durable cart (DB), max 1,000 chars; never in the cookie |
| Cart shipping line | "desde $<cheapest active method>" / "¡Gratis!" when eligible; dead `SHIPPING_FLAT` code removed |
| Legal pages | Out of scope (owner will provide text later) |

## Part 1 — Cart expiry

- `ShoppingCart::IDLE_TTL = 4.hours`; `CartInventoryHold::HOLD_DURATION` stays
  4 h and every cart mutation **renews all active holds of that cart** to
  `clock_timestamp() + 4 h`, so holds and cart expire together.
- New terminal status **`expired`**: `closed_at` required,
  `anonymous_token_digest` null. Migration replaces the
  `shopping_carts_lifecycle_invariants` check constraint to allow it.
  Lines are kept (history); holds are deleted.
- `ShoppingCarts::ExpireCart`
  - `.stale?(cart)` → active, `last_activity_at < IDLE_TTL.ago`, has lines.
  - `.call(cart)` → locks the cart, re-checks `stale?`, deletes its holds,
    sets `expired` + `closed_at`; returns true when it expired the cart.
- **On read** (`Storefront::Persistent#persistent_cart`): a stale active cart
  is expired; the storefront reports `expired?`, its session projection is
  rewritten empty (`SessionProjection.write(session, nil, {})`) so the login
  import never re-imports it. The next add creates a new active cart.
- **Visitor cart**: `ShoppingCarts::SessionCartExpiry` keeps
  `session['cart_touched_at']` (epoch seconds), stamped on every successful
  add / set / remove; a stale session cart is cleared on read
  (`Storefront::Anonymous#cart`) and is not imported at login
  (`Storefront::Persistent#bind_session!` clears it first). A cart with no
  stamp (pre-existing) gets stamped on first read, never expired blindly.
- **Notice**: `ApplicationController` before_action (HTML / turbo_stream,
  storefront controllers only — not `admin/*`, `api/*`) sets
  `flash.now[:warning]` when the storefront reports `expired?`.
- **Checkout**: `CheckoutsController` redirects to the cart with the same
  message (persistent flash) when the cart expired; no order is created.
- **Job**: `Carts::ExpireIdleCartsJob` every 15 min expires stale durable
  carts so units free up even if the customer never returns.

## Part 2 — Order alerts (read-only)

`SaleOrders::Alerts` (SQL aggregates; no per-order Ruby loading):

- `stale_pending` — `status = 'Pending'`, `created_at < 30.days.ago`; selects
  `paid_amount` (sum of Completed payments) and `held_units` (inventories
  reserved / pre_reserved / sold on the order).
- `overpaid` — not Canceled, `paid_amount > total_order_value + 0.01`.
- `inconsistent` — Pending with at least one inventory row `sold`.
- `counts` — the three counts for the dashboard.

`Admin::OrderAlertsController#index` at `/admin/order_alerts`, sidebar entry
"Alertas de órdenes" under Ventas, and one dashboard alert ("N órdenes
requieren atención") when any count is positive. Each row links to the sale
order. Nothing on the page mutates data.

## Part 3 — Checkout fixes

- Notes: `shopping_carts.checkout_notes` (text). `set_checkout_notes` stores
  `notes.to_s.strip.first(1000)` on the durable cart; `checkout_notes` reads it.
  The textarea gets `maxlength="1000"` and a label. Session no longer carries
  notes.
- Cart shipping line: `Shipping::Calculator.cheapest_active_rate` (min
  `base_cost` of active methods); cart shows "¡Gratis!" if free-shipping
  eligible, else "desde $X", else "A calcular" when no rate exists.
  `Cart::SHIPPING_FLAT`, `#shipping_cost`, `#grand_total` removed (unused).

## Testing (TDD)

- ExpireCart: stale vs fresh vs empty; holds deleted; status/closed_at; race
  (a mutation that renewed activity before the lock → not expired).
- Hold renewal on add / set / remove keeps holds alive while active.
- Storefront: persistent stale cart → empty cart + `expired?`; new add creates
  a new cart; visitor stale session cart cleared; stale visitor cart not
  imported at login; unstamped visitor cart stamped, not expired.
- Request: notice shown on cart page; checkout redirect when expired;
  notes of 5,000 chars → step 2 OK, stored 1,000 chars, no CookieOverflow.
- Job expires only stale carts with lines; recurring.yml contract spec
  updated (`carts_expire_idle_every_15_minutes`).
- Alerts: each query (thresholds, overpaid tolerance, inconsistent); admin
  page renders rows with links, non-admin denied; dashboard alert appears.
- Cart page shows "desde $60" / "¡Gratis!".
