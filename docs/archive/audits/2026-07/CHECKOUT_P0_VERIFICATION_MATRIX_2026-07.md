# Checkout P0 Verification Matrix (2026-07)

## Scope and evidence

- Branch: `fix/checkout-p0-foundation-2026-07`
- Final consolidated P0 set: 176 examples, 0 failures.
- Final full suite: 832 examples, 0 failures (project-default system-spec exclusion applies).
- Runtime confirmation-page request: `ActionView::Template::Error` from the missing `SaleOrder#shipping_address` method.
- Production shipping configuration observed locally: `envio_estandar` (99), `envio_express` (199), `recoger_tienda` (0), and `envio_local` (149). No customer or credential data was inspected.
- Fiscal boundary: the existing setting describes an added-tax calculation. P0 will make that calculation consistent and snapshot it on the order. IVA-included presentation, deposit tax allocation, CFDI treatment, refunds, and historical reconstruction remain outside this branch.

## Verification matrix

### P0-01 - Confirmation page cannot render

- **Verification:** Confirmed / Critical
- **Current behavior:** A newly-created order redirects to the confirmation route, but rendering calls methods and a route helper that do not exist. Line prices may also be nil.
- **Files/methods:** `app/views/checkouts/thank_you.html.erb:35`, `:45`, `:107`, `:110`, `:119`, `:170`; `SaleOrder#order_shipping_address` at `app/models/sale_order.rb:30`.
- **Evidence:** An authenticated request for a real test order raised `ActionView::Template::Error: undefined method 'shipping_address' for SaleOrder`. Static route inspection confirms the storefront route is `catalog_path`, not `products_path`.
- **Customer impact:** The customer sees a 500 immediately after placing an order and cannot verify whether it succeeded.
- **Data-integrity/business impact:** Retrying can cause order uncertainty and duplicate-payment/support risk even though the idempotency key protects many repeat submissions.
- **Regression test:** Authenticated request renders the thank-you page with address snapshot, shipping method, item price, subtotal, total, and storefront/order-history links.
- **Proposed fix:** Render exclusively from persisted snapshots and order fields: `order_shipping_address`, its `shipping_method`, `subtotal`, and a non-nil persisted `unit_final_price`; use `catalog_path`.
- **Complexity / DB change:** Low / No.

### P0-02 - Production shipping codes silently become free shipping

- **Verification:** Confirmed / Critical
- **Current behavior:** `Shipping::Calculator.resolve` maps only `standard`, `express`, and `pickup`; every unknown code silently falls back to `standard`, whose calculator returns zero. Configured `ShippingMethod#base_cost` is ignored. The helper rescues every error and returns zero. After making the calculator strict, a method disabled between steps would raise on the review page and final submission unless the controller revalidates it.
- **Files/methods:** `app/services/shipping/calculator.rb:14-22`; calculators under `app/services/shipping/calculators`; `CheckoutsHelper#checkout_shipping_cost` at `app/helpers/checkouts_helper.rb:7-17`; `CheckoutsController#step3` and `#complete` at `app/controllers/checkouts_controller.rb:58-153`; `Checkout::CreateOrder#call` at `app/services/checkout/create_order.rb:30-31`.
- **Evidence:** Production-like active codes (`envio_estandar`, `envio_express`, `recoger_tienda`, `envio_local`) do not exist in the registry. Resolver evaluation selects `StandardCalculator`, which returns `0`. Focused stale-selection requests produced `Shipping::Calculator::UnknownMethodError` from both review rendering and final submission.
- **Customer impact:** The checkout displays and charges zero shipping for chargeable methods.
- **Data-integrity/business impact:** Persisted order and payment totals omit configured shipping revenue; the store absorbs fulfillment cost.
- **Regression test:** Active production-code methods quote their decimal `base_cost`; pickup remains zero; the established free-shipping threshold is applied deterministically; inactive/unknown methods fail closed instead of becoming free; stale selections return to step 2 without an order or a 500.
- **Proposed fix:** Resolve an active `ShippingMethod` explicitly, use its snapshotted quote as the source of truth, and raise a typed error for missing/inactive codes. Revalidate the stored selection before rendering/recalculating. Keep legacy aliases only for existing data/tests.
- **Complexity / DB change:** Medium / No.

### P0-03 - Cart, review, order, and Payment totals diverge

- **Verification:** Confirmed / Critical
- **Current behavior:** `Cart#grand_total` adds estimated shipping and optional IVA. Checkout reviews a calculator quote. Order creation hardcodes tax to zero, recalculates from line totals plus its shipping result, and then creates a Payment from that persisted total.
- **Files/methods:** `Cart#tax_amount`, `#shipping_cost`, and `#grand_total` at `app/models/cart.rb:100-118`; `Checkout::CreateOrder#call` at `app/services/checkout/create_order.rb:30-31`, `:105-115`, `:173-189`; `SaleOrder#compute_financials` at `app/models/sale_order.rb:263-286`.
- **Evidence:** Static evaluation shows tax-enabled cart total includes IVA while the created order always stores `tax_rate=0` and `total_tax=0`; shipping has the defect in P0-02.
- **Customer impact:** The amount reviewed can differ from the order/payment amount.
- **Data-integrity/business impact:** Order, receivable, and payment records can disagree with the amount represented to the customer.
- **Regression test:** For tax disabled/enabled and below/above free-shipping threshold, review quote, persisted subtotal/tax/shipping/total, and initial Payment amount are exactly equal.
- **Proposed fix:** Introduce one server-side checkout total calculation using decimal arithmetic and feed its values into the review helper, `SaleOrder`, and Payment. Do not accept browser totals.
- **Complexity / DB change:** Medium / No.

### P0-04 - Current IVA setting is not snapshotted by checkout

- **Verification:** Partially confirmed / High
- **Current behavior:** The admin can enable `tax_enabled` and set `tax_rate_percent`; `Cart` calculates added tax, but order creation ignores both. The local current setting is disabled, so zero-tax orders are not presently inconsistent solely because of IVA.
- **Files/methods:** `app/views/admin/settings/index.html.erb:214-225`; `Cart#tax_enabled?` and `#tax_rate_percent` at `app/models/cart.rb:120-132`; `Checkout::CreateOrder#call` at `app/services/checkout/create_order.rb:105-110`.
- **Evidence:** Existing specs pass with tax disabled. Enabling the existing setting makes cart IVA nonzero while checkout persists zero.
- **Customer impact:** Enabling the advertised admin control changes the displayed amount but not the charged/persisted tax.
- **Data-integrity/business impact:** Tax and receivable snapshots become inaccurate.
- **Regression test:** Enabled added-tax setting at 16% stores decimal `tax_rate=16`, exact `total_tax`, and matching total/payment; changing the setting later does not change the order.
- **Proposed fix:** Snapshot the current added-tax rate and calculated amount on `SaleOrder`. Do not infer tax for historical rows or implement included-price/deposit/refund fiscal treatment in P0.
- **Complexity / DB change:** Low / No (existing snapshot columns).

### P0-05 - Availability rules disagree across storefront, cart, and checkout

- **Verification:** Confirmed / Critical
- **Current behavior:** `Product#sellable_inventory` requires free located `available` or free `in_transit`; `current_on_hand` counts all available rows, including assigned/unlocated rows. Checkout collectibles count status only. The splitter consumes the broad methods. Cart JSON summaries call the splitter without the line condition and can report brand-new availability for a collectible line.
- **Files/methods:** `Product#current_on_hand`, `#in_transit_count`, `#split_immediate_and_pending`, and `#sellable_inventory` at `app/models/product.rb:511-634`; `InventoryServices::AvailabilitySplitter#call` at `app/services/inventory_services/availability_splitter.rb:19-39`; `CartItemsController#aggregate_pending` at `app/controllers/cart_items_controller.rb:225-245`; `Checkout::CreateOrder#call` at `app/services/checkout/create_order.rb:39-99`.
- **Evidence:** Query comparison demonstrates different predicates for the same inventory row. Assigned and unlocated available inventory can pass checkout validation although it is not storefront-sellable. A mint line backed by one mint in-transit unit returned a JSON in-transit summary of zero because the wrapper defaulted to brand-new.
- **Customer impact:** Products can appear purchasable but fail later, or checkout can accept stock that should not be offered.
- **Data-integrity/business impact:** Incorrect reservations and oversell risk.
- **Regression test:** Located/free available and free in-transit inventory count; assigned/unlocated/incompatible-condition inventory does not; catalog/cart/splitter/checkout return the same quantities; cart summaries preserve the line condition.
- **Proposed fix:** Add canonical `Inventory` sellable scopes and make Product, splitter, cart validation, checkout validation, and allocation use them with condition.
- **Complexity / DB change:** Medium / No.

### P0-06 - Inventory allocation is not row-locked

- **Verification:** Partially confirmed / Critical
- **Current behavior:** Checkout locks Product rows, which protects the existing checkout-vs-checkout path. Allocation selects assignable Inventory rows without `FOR UPDATE`; background/admin allocation can race checkout.
- **Files/methods:** product lock in `app/services/checkout/create_order.rb:65-70`; allocation query in `app/models/concerns/inventory_syncable.rb:75-79`; auto-allocation service under `app/services/sale_orders/auto_assign_inventory_service.rb`.
- **Evidence:** Existing two-checkout concurrency examples pass. SQL path inspection confirms Inventory candidates are not locked, so cross-path serialization is absent; that race was not reliably reproduced in the baseline suite.
- **Customer impact:** Two workflows may believe they reserved the last piece.
- **Data-integrity/business impact:** Lost assignment updates, order shortfalls, and oversell risk.
- **Regression test:** Allocation emits a locked candidate query and concurrent allocation attempts cannot attach one Inventory row to two lines.
- **Proposed fix:** Centralize reservation in a transaction that locks existing assignments and ordered candidate Inventory rows before validation/update. Retain Product locking as an additional checkout guard.
- **Complexity / DB change:** High / No.

### P0-07 - Allocation crosses order lines and item conditions

- **Verification:** Confirmed / Critical
- **Current behavior:** Sale allocation counts rows by `product_id + sale_order_id`, does not filter `item_condition`, and initially omits `sale_order_item_id`. A later bulk backfill can attach all unlinked rows to the first matching line.
- **Files/methods:** `InventorySyncable#sync_inventory_for_sale` at `app/models/concerns/inventory_syncable.rb:66-97`; `SaleOrderItem#inventory_units` at `app/models/sale_order_item.rb:56-58`; soft backfill at `app/services/checkout/create_order.rb:195-203`.
- **Evidence:** Static query inspection; `inventories.sale_order_item_id` already exists and is indexed but is not used as the allocation identity.
- **Customer impact:** A customer can receive the wrong condition/variant or an order line can appear reserved when another line consumed its stock.
- **Data-integrity/business impact:** Traceability, fulfillment accuracy, margin reporting, and inventory ownership are corrupted.
- **Regression test:** Two lines for one product with different conditions each receive only matching rows linked directly to their `sale_order_item_id`.
- **Proposed fix:** Make `sale_order_item_id` the assignment owner, filter candidates by condition, and remove ambiguous product/order backfill.
- **Complexity / DB change:** High / No.

### P0-08 - Reservation failures are silently accepted in production or converted to non-retryable results

- **Verification:** Confirmed / Critical
- **Current behavior:** `InventorySyncable#sync_inventory_records` rescues all errors and re-raises only outside production. Checkout can therefore commit an order with no valid reservation in production. Preorder batch allocation converts exceptions to `false`, and auto-assignment converts exceptions to a result, preventing the retry-enabled job from retrying.
- **Files/methods:** `app/models/concerns/inventory_syncable.rb:21-25`; `Preorders::PreorderAllocator.batch_allocate` at `app/services/preorders/preorder_allocator.rb:14-32`; `SaleOrders::AutoAssignInventoryService#call` at `app/services/sale_orders/auto_assign_inventory_service.rb:34-67`.
- **Evidence:** Direct environment branch in the checkout callback. Focused regressions forced the two background reservation services to fail and observed that neither raised.
- **Customer impact:** The customer receives a successful order for stock that was not secured.
- **Data-integrity/business impact:** Orders and inventory diverge silently; remediation depends on logs.
- **Regression test:** Forced reservation failure propagates in every environment and rolls back the order, lines, address, inventory changes, and Payment; unexpected batch/background allocation errors propagate to callers and Active Job retry handling.
- **Proposed fix:** Log/report with non-sensitive identifiers, then always raise inside the checkout transaction and at reservation service boundaries. Continue representing ordinary inventory shortfalls as pending results, not exceptions.
- **Complexity / DB change:** Low / No.

### P0-09 - Sale of in-transit stock uses the wrong state

- **Verification:** Confirmed / High
- **Current behavior:** Every assigned candidate is changed to `reserved`, including `in_transit`. Existing order transitions already understand `pre_reserved -> pre_sold`, but checkout never creates `pre_reserved`.
- **Files/methods:** `InventorySyncable#reserve_inventory_items` at `app/models/concerns/inventory_syncable.rb:99-107`; status enum at `app/models/inventory.rb:50-54`; order transition logic in `app/models/sale_order.rb` (inventory status synchronization).
- **Evidence:** Unconditional `status: :reserved` assignment.
- **Customer impact:** Staff and customer availability expectations treat incoming pieces as physically ready.
- **Data-integrity/business impact:** Warehouse status, fulfillment timing, and preorder/in-transit reporting are false.
- **Regression test:** Free `available` becomes `reserved`; free `in_transit` becomes `pre_reserved`; confirmation maps them to `sold` and `pre_sold` respectively.
- **Proposed fix:** Preserve physical state semantics during line-specific reservation and release (`reserved -> available`, `pre_reserved -> in_transit`).
- **Complexity / DB change:** Medium / No.

### P0-10 - Order and initial Payment are not atomic

- **Verification:** Confirmed / Critical
- **Current behavior:** Order, lines, inventory, and address commit first. Payment is created afterward, and any Payment error is swallowed.
- **Files/methods:** transaction ends at `app/services/checkout/create_order.rb:175`; Payment block at `:182-193`.
- **Evidence:** Transaction boundary and unconditional rescue are explicit in the service.
- **Customer impact:** Checkout reports success while no payable record exists.
- **Data-integrity/business impact:** Orphan receivables and manual reconciliation.
- **Regression test:** A forced Payment persistence failure leaves no order, line, address, reservation, preorder reservation, or Payment.
- **Proposed fix:** Create the initial Payment inside the same transaction after final server total calculation and let failures roll back.
- **Complexity / DB change:** Medium / No.

### P0-11 - Checkout writes incorrect financial meanings

- **Verification:** Confirmed / Critical
- **Current behavior:** `unit_cost` receives the customer selling price, `unit_final_price` is omitted, and inventory `sold_price` converts the nil final price to `0.0`.
- **Files/methods:** line creation at `app/services/checkout/create_order.rb:134-143`; sold-price assignment at `app/models/concerns/inventory_syncable.rb:99-106`; line schema at `db/schema.rb:564-583`.
- **Evidence:** Attribute assignment inspection; confirmation arithmetic also depends on the omitted field.
- **Customer impact:** Confirmation can fail or show incorrect line amounts.
- **Data-integrity/business impact:** Cost, revenue, margin, and inventory sale-price reporting are corrupted.
- **Regression test:** Checkout stores acquisition cost separately from selling/final price; line total is final price times quantity; assigned inventory `sold_price` equals final customer unit price.
- **Proposed fix:** Snapshot `Product#average_purchase_cost` as unit cost for this P0 path, and the server-resolved customer price as both unit selling and final price. Use decimal arithmetic.
- **Complexity / DB change:** Medium / No.

### P0-12 - Preorder reservations are orphaned from their originating line

- **Verification:** Confirmed / Critical
- **Current behavior:** Checkout deliberately creates `PreorderReservation` with `sale_order: nil` and only embeds SO/SOI IDs in free text. The allocator can create another order or find/increment an existing product line. Line reduction/deletion callbacks select reservations by order plus product instead of origin line; adding a restrictive FK without moving cleanup before deletion would also make linked lines undeletable.
- **Files/methods:** `app/services/checkout/create_order.rb:145-156`; `app/models/preorder_reservation.rb:3-7`; `app/services/preorders/preorder_allocator.rb`; preorder mutation callbacks at `app/models/sale_order_item.rb:120-205`.
- **Evidence:** Baseline schema has `sale_order_id` but no `sale_order_item_id`; checkout assigns nil explicitly. Focused isolation regressions showed reducing a second same-product line mutated the first reservation, and deletion raised `PG::ForeignKeyViolation` before the after-destroy cleanup.
- **Customer impact:** Incoming stock may be allocated to a new/incorrect order or duplicate the purchased quantity.
- **Data-integrity/business impact:** Preorder obligation traceability and fulfillment quantities are unreliable.
- **Regression test:** Checkout reservation belongs to the original order and line; allocator assigns stock to that line without creating or incrementing another order line; quantity reduction and deletion affect only reservations linked to that exact line.
- **Proposed fix:** Add nullable `sale_order_item_id` foreign key/index, populate both links atomically, make allocation honor the original line, and perform line-scoped cancellation cleanup before deletion.
- **Complexity / DB change:** High / Yes (one normalized linkage column and FK).

### P0-13 - PostgreSQL idempotency race recovery depends on message text

- **Verification:** Partially confirmed / High
- **Current behavior:** Secure token comparison, scoped model validation, and a unique database index already exist. The race rescue only handles exceptions whose message contains `sale_orders.index_sale_orders_on_user_and_idempotency`, which is not PostgreSQL's stable constraint representation. A real second POST after success cannot reach recovery because session cleanup empties the cart/token and the before-action redirects to the cart.
- **Files/methods:** `CheckoutsController#complete` and `#ensure_cart_not_empty` at `app/controllers/checkouts_controller.rb:5-179`; SaleOrder validation at `app/models/sale_order.rb:42`; unique index in `db/schema.rb`.
- **Evidence:** Existing duplicate-submission tests pass through the pre-query path. The true database-race path is untested; PostgreSQL reports the constraint name separately and commonly omits the table-prefixed string expected here. A sequential double-submit regression created one order, then observed the repeated POST redirect to `/cart` instead of the existing confirmation.
- **Customer impact:** A rare double-submit race can surface a 500 even though one order succeeded.
- **Data-integrity/business impact:** Database uniqueness still prevents duplication, but the customer receives an ambiguous failure and may contact support or retry payment.
- **Regression test:** A PostgreSQL-shaped `RecordNotUnique` raised after a concurrent order is inserted recovers that scoped order and redirects to confirmation; an unrelated uniqueness error is re-raised; a repeated successful POST recovers after cart/token cleanup without creating an order.
- **Proposed fix:** Let `complete` perform idempotency recovery before mutable cart/shipping/payment validation. Recover only a current-user order with the submitted token, and after `RecordNotUnique` recover by current user plus token; if no matching order exists, re-raise rather than parsing adapter-specific message text.
- **Complexity / DB change:** Low / No.

### P0-14 - Cart mutations do not invalidate the loaded item cache

- **Verification:** Confirmed / High
- **Current behavior:** `Cart#load_items` memoizes in `@load_items`, but `#invalidate_cache!` and `#reload_items!` clear an unused `@items` variable. Once items are read in a request, later quantity updates or removals can return the old lines and totals.
- **Files/methods:** `Cart#invalidate_cache!` and `#reload_items!` at `app/models/cart.rb:52-72`.
- **Evidence:** Regression example loaded quantity 1, updated the same session cart to quantity 2, and still read quantity 1 (`expected: 2, got: 1`).
- **Customer impact:** Turbo/JSON cart feedback can show stale quantities, counters, and totals immediately after a mutation.
- **Data-integrity/business impact:** A later checkout operation in the same request object can calculate from stale cart data, undermining the single server-side totals source.
- **Regression test:** Load items, update the quantity, verify the loaded quantity changes; remove the item and verify the loaded collection is empty.
- **Proposed fix:** Invalidate the actual `@load_items` memo and make explicit reload call the same invalidation method.
- **Complexity / DB change:** Low / No.

### P0-15 - Hidden collectible inventory influences the customer price

- **Verification:** Confirmed / High
- **Current behavior:** Product discovery groups and prices the canonical sellable scope, but cart and JSON line-price helpers average every `available` unit for a condition, including assigned and unlocated rows.
- **Files/methods:** `Cart#price_for_condition` at `app/models/cart.rb:199-208`; `CartItemsController#price_for_condition` at `app/controllers/cart_items_controller.rb:204-210`; canonical discovery calculation at `Product#available_by_condition` in `app/models/product.rb:527-553`.
- **Evidence:** With one located/sellable mint unit at MXN 200 and one unlocated mint unit at MXN 1,000, the cart charged the MXN 600 average instead of MXN 200.
- **Customer impact:** The price can change between product discovery and cart, based on inventory the customer cannot buy.
- **Data-integrity/business impact:** Persisted line revenue can be based on the wrong inventory population even though the browser cannot submit its own price.
- **Regression test:** Assigned/unlocated collectible units do not influence the cart condition price; the cart and JSON response use the same server method.
- **Proposed fix:** Centralize the current representative condition-price rule and calculate it from `Product#sellable_inventory`. Exact physical-piece selection remains a later branch.
- **Complexity / DB change:** Low / No.

## Already protected or not reproduced

### Server-side line pricing and totals

- **Verification:** Already fixed for browser tampering / High protection.
- **Evidence:** `Cart#build_items` resolves Product and condition price server-side (`app/models/cart.rb:177-209`); checkout uses those server objects and `SaleOrder#recalculate_totals!` rather than request totals.
- **Residual test:** Submit extra total/price/tax/discount parameters and assert they are ignored.
- **Action:** Preserve this behavior while centralizing calculations.

### Checkout-vs-checkout overselling

- **Verification:** Not reproducible in the covered path.
- **Evidence:** Existing concurrency examples pass and the Product rows are pessimistically locked (`app/services/checkout/create_order.rb:65-70`).
- **Residual risk:** Background/admin allocation does not take the same Product lock and Inventory candidates are not row-locked (P0-06).
- **Action:** Keep Product locking and add Inventory locking in the common allocator.

### Delivered inventory without a physical location

- **Verification:** Confirmed invariant and resolved regression.
- **Evidence:** `spec/models/purchase_order_spec.rb:212` now proves that a Delivered PO unit remains excluded from `Inventory.customer_sellable` while `inventory_location_id` is nil, then becomes allocatable after a valid location is assigned. Focused result: 19 examples, 0 failures.
- **Decision in this branch:** Customer allocation has no unlocated fallback. Admin receiving must assign a valid physical location before the unit can be allocated to a customer.
- **Customer/data impact:** Checkout cannot promise a physically unlocated delivered item; order-line allocation begins only after warehouse traceability exists.
- **Admin-only review:** No existing admin workflow requires an unlocated unit to be customer-allocatable. Internal inspection and location assignment remain available without weakening the customer scope.

### Database uniqueness for idempotency

- **Verification:** Already fixed.
- **Evidence:** Scoped unique database index and model validation exist; baseline duplicate-token examples pass.
- **Action:** Preserve the index and replace only brittle recovery behavior (P0-13).

## Dependency order

1. P0-01 confirmation rendering.
2. P0-02 through P0-04 shipping/tax/total source of truth.
3. P0-05 through P0-09 canonical availability and locked line allocation.
4. P0-10 and P0-11 atomic Payment and financial snapshots.
5. P0-12 preorder origin linkage and allocator behavior.
6. P0-13 adapter-safe idempotency recovery.

## Final stabilization status

All confirmed items P0-01 through P0-15 are implemented within the approved branch scope. P0-04 remains intentionally limited to the application's current IVA-added mode and historical order snapshot columns; IVA-included pricing, deposit/penalty accounting, CFDI decisions, and refund ledgers remain later work.

Additional stabilization completed after the initial matrix:

- Active checkout payment methods are restricted to codes supported by the persisted `Payment` enum; unsupported active admin records fail closed.
- In-transit lines render as awaiting arrival in review, confirmation, and customer order detail.
- Cancelling an order cancels the preorder reservation linked to its original `SaleOrderItem` without deleting the historical link.
- Cart and customer order tables no longer overflow a 390 px viewport; quantity changes update both desktop and mobile line totals.
- Bullet remains enabled during checkout. The reservation callback no longer loads the shared Product once per Inventory row. No affected cart, checkout, confirmation, customer order, or admin order view emitted a Bullet warning after a clean server restart.

Final evidence:

- Purchase-order invariant: 19 examples, 0 failures.
- Checkout: 34 examples, 0 failures.
- Cart: 27 examples, 0 failures.
- Focused allocation: 32 examples, 0 failures.
- Preorder-related coverage: 145 examples, 0 failures.
- Payment: 10 examples, 0 failures.
- Consolidated P0: 176 examples, 0 failures.
- Full RSpec: 832 examples, 0 failures.
- `bin/rails zeitwerk:check`: pass (only the existing mailer-preview eager-load notice).
- `git diff --check`: clean.
- Migration `20260724000001`: reversible in the disposable test database; down succeeded, status was down, and reapplication succeeded.
- Browser smoke: stock, in-transit, preorder, duplicate submission, confirmation, and desktop/mobile rendering passed against `inventory_app_p0_smoke`; database assertions confirmed exact totals, one initial Payment, reserved/pre-reserved states, and original-line preorder linkage.
- Project RuboCop command: still nonzero because of the repository-wide pre-existing lint backlog. The branch-local checkout indentation, callback alignment, and redundant association option found during stabilization were corrected.
