# Cart Expiry & Order Alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shopping carts expire 4 h after their last change (durable and visitor), releasing held units with a customer notice; sale orders are never auto-cancelled but stale-pending, overpaid and inconsistent orders are reported on an admin "Alertas de órdenes" page and dashboard; checkout notes move off the cookie; the cart shows "Envío desde $X".

**Architecture:** A new terminal `expired` cart status (check-constraint migration) set by `ShoppingCarts::ExpireCart`, invoked on read by the storefront and every 15 min by `Carts::ExpireIdleCartsJob`; every cart mutation renews its holds. Visitor carts use a session timestamp (`ShoppingCarts::SessionCartExpiry`). `SaleOrders::Alerts` computes the three alert sets in SQL for `Admin::OrderAlertsController` and the dashboard. Notes live in `shopping_carts.checkout_notes`.

**Tech Stack:** Rails 8.0.1, PostgreSQL (check constraints, `clock_timestamp()`), Solid Queue recurring tasks, RSpec request/service specs.

**Spec:** `docs/superpowers/specs/2026-10-11-cart-expiry-and-order-alerts-design.md`

## Global Constraints

- Ruby: `~/.rvm/bin/rvm 3.2.3 do <cmd>`. Test DB: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bin/rails db:test:prepare`; never destructive tasks on `inventory_app_development`; `bin/rails db:migrate` (development) allowed.
- Do not edit app code or run other rspec processes while the full suite runs.
- Sale orders are never modified by any code in this plan.
- Idle TTL **4 hours** after the last change; viewing does not renew. Pending-alert threshold **30 days**; overpaid tolerance **0.01**.
- Customer notice text exactly: `Tu carrito venció tras 4 horas sin actividad y liberamos las piezas apartadas.`
- Checkout notes max **1,000** chars, stored on the durable cart, never in the session.
- Prod is a 512 MB dyno: alert queries aggregate in SQL; no loading every order.
- `config/recurring.yml` has a contract spec (`spec/config/recurring_schedule_spec.rb`) that lists exact production keys — update it with any new key.
- Spec traps: `create(:product)` seeds inventory unless `skip_seed_inventory: true`; quick product needs `selling_price`.
- After code changes run `graphify update .`.

## Review Focus

1. **A customer adds an item at 3:59 of idle time while the job expires the cart** — exactly one wins: either the add renews activity and the cart stays, or the cart expires and the add lands in a new cart; never an add into an expired cart. → Task 1 race spec (re-check under lock) + mutation path uses `ActiveCartResolver` which only finds `active`.
2. **The session projection of an expired durable cart is re-imported at login** — must not happen. → Task 3 spec.
3. **Checkout confirmed after the cart expired mid-checkout** — no order, clear message. → Task 3 request spec.
4. **Overpaid order whose payments are still Pending** — not reported (only Completed count). → Task 4 spec.
5. **Notes of 5,000 characters** — no CookieOverflow; stored 1,000. → Task 5 request spec.

---

### Task 1: `expired` cart status and `ShoppingCarts::ExpireCart`

**Files:**
- Create: `db/migrate/20261011120000_add_expired_status_and_notes_to_shopping_carts.rb`, `app/services/shopping_carts/expire_cart.rb`, `spec/services/shopping_carts/expire_cart_spec.rb`
- Modify: `db/schema.rb`, `app/models/shopping_cart.rb`, `spec/factories/shopping_carts.rb`

**Interfaces:**
- Produces: `ShoppingCart::IDLE_TTL = 4.hours`; status `'expired'`; column `checkout_notes` (text, used in Task 5); `ShoppingCarts::ExpireCart.stale?(cart) → Boolean`, `.call(cart) → Boolean`; factory trait `:expired`.

- [ ] **Step 1: Failing spec** — `spec/services/shopping_carts/expire_cart_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ShoppingCarts::ExpireCart do
  let(:location) { create(:inventory_location) }
  let(:user) { create(:user) }
  let(:product) { create(:product, skip_seed_inventory: true) }

  def available_unit
    inventory = create(:inventory, product: product, status: :damaged)
    inventory.update_columns(status: Inventory.statuses['available'],
                             item_condition: Inventory.item_conditions['brand_new'],
                             inventory_location_id: location.id)
    inventory
  end

  def cart_with_line(idle_for:)
    available_unit
    ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new')
    cart = ShoppingCarts::ActiveCartResolver.find(user)
    cart.update_columns(last_activity_at: idle_for.ago)
    cart
  end

  it 'considera vencido un carrito activo con líneas y más de 4 h sin cambios' do
    expect(described_class.stale?(cart_with_line(idle_for: 5.hours))).to be(true)
  end

  it 'no considera vencido un carrito con actividad reciente' do
    expect(described_class.stale?(cart_with_line(idle_for: 3.hours))).to be(false)
  end

  it 'no considera vencido un carrito vacío' do
    cart = ShoppingCarts::ActiveCartResolver.find_or_create!(user)
    cart.update_columns(last_activity_at: 5.hours.ago)
    expect(described_class.stale?(cart)).to be(false)
  end

  it 'lo marca vencido, conserva sus líneas y libera sus apartados' do
    cart = cart_with_line(idle_for: 5.hours)
    expect(CartInventoryHold.for_cart(cart).count).to eq(1)

    expect(described_class.call(cart)).to be(true)
    cart.reload
    expect(cart.status).to eq('expired')
    expect(cart.closed_at).to be_present
    expect(cart.shopping_cart_items.count).to eq(1)
    expect(CartInventoryHold.for_cart(cart).count).to eq(0)
    expect(ShoppingCarts::ActiveCartResolver.find(user)).to be_nil
  end

  it 'no lo vence si recibió actividad antes de tomar el candado' do
    cart = cart_with_line(idle_for: 5.hours)
    stale_copy = ShoppingCart.find(cart.id)
    cart.update_columns(last_activity_at: Time.current) # otra pestaña lo tocó
    expect(described_class.call(stale_copy)).to be(false)
    expect(cart.reload.status).to eq('active')
  end

  it 'permite el estado expired sólo con closed_at (restricción de la base)' do
    cart = create(:shopping_cart, :owned)
    expect { cart.update_columns(status: 'expired') }.to raise_error(ActiveRecord::StatementInvalid, /lifecycle_invariants/)
    expect { cart.update_columns(status: 'expired', closed_at: Time.current) }.not_to raise_error
  end
end
```
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/shopping_carts/expire_cart_spec.rb` — Expected: FAIL `uninitialized constant ShoppingCarts::ExpireCart`.

- [ ] **Step 2: Migration** — `db/migrate/20261011120000_add_expired_status_and_notes_to_shopping_carts.rb`:
```ruby
# frozen_string_literal: true

# Carritos que vencen tras 4 h sin cambios (estado terminal `expired`) y notas
# de checkout guardadas en el carrito en vez de la cookie de sesión.
class AddExpiredStatusAndNotesToShoppingCarts < ActiveRecord::Migration[8.0]
  OLD = <<~SQL.squish
    status::text = 'active'::text AND sale_order_id IS NULL AND converted_at IS NULL AND closed_at IS NULL AND merged_into_cart_id IS NULL
    OR status::text = 'converted'::text AND sale_order_id IS NOT NULL AND converted_at IS NOT NULL AND closed_at IS NOT NULL AND anonymous_token_digest IS NULL
    OR status::text = 'merged'::text AND merged_into_cart_id IS NOT NULL AND closed_at IS NOT NULL AND anonymous_token_digest IS NULL
    OR status::text = 'cleared'::text AND closed_at IS NOT NULL AND anonymous_token_digest IS NULL
  SQL
  NEW = "#{OLD} OR status::text = 'expired'::text AND closed_at IS NOT NULL AND anonymous_token_digest IS NULL".freeze

  def up
    add_column :shopping_carts, :checkout_notes, :text
    remove_check_constraint :shopping_carts, name: 'shopping_carts_lifecycle_invariants'
    add_check_constraint :shopping_carts, NEW, name: 'shopping_carts_lifecycle_invariants'
  end

  def down
    execute "UPDATE shopping_carts SET status = 'cleared' WHERE status = 'expired'"
    remove_check_constraint :shopping_carts, name: 'shopping_carts_lifecycle_invariants'
    add_check_constraint :shopping_carts, OLD, name: 'shopping_carts_lifecycle_invariants'
    remove_column :shopping_carts, :checkout_notes
  end
end
```
Run: `~/.rvm/bin/rvm 3.2.3 do bin/rails db:migrate && RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bin/rails db:test:prepare` — Expected: schema.rb gains `checkout_notes` and the constraint includes `'expired'`.

- [ ] **Step 3: Model + factory**
`app/models/shopping_cart.rb`:
- `STATUSES = %w[active converted merged cleared].freeze` → `STATUSES = %w[active converted merged cleared expired].freeze`
- below it add:
```ruby
  # Un carrito con líneas y sin cambios durante este tiempo vence (ver
  # ShoppingCarts::ExpireCart). Coincide con la vigencia de los apartados.
  IDLE_TTL = 4.hours
```
- `validate :cleared_cart_requirements` → add `validate :expired_cart_requirements` below it, and the method next to `cleared_cart_requirements`:
```ruby
  def expired_cart_requirements
    return unless status == 'expired'

    errors.add(:closed_at, "can't be blank for an expired cart") if closed_at.blank?
  end
```
`spec/factories/shopping_carts.rb`, after `trait :cleared … end`:
```ruby
    trait :expired do
      status { 'expired' }
      closed_at { Time.current }
    end
```

- [ ] **Step 4: Service** — `app/services/shopping_carts/expire_cart.rb`:
```ruby
# frozen_string_literal: true

module ShoppingCarts
  # Vence un carrito durable que lleva ShoppingCart::IDLE_TTL sin cambios:
  # libera sus apartados y lo cierra como `expired`. Sus líneas se conservan
  # como historial; el siguiente "agregar" crea un carrito nuevo. Las órdenes
  # de venta nunca se tocan aquí.
  class ExpireCart
    def self.stale?(cart)
      cart.status == 'active' &&
        cart.last_activity_at < ShoppingCart::IDLE_TTL.ago &&
        cart.shopping_cart_items.exists?
    end

    # true si lo venció. Se re-evalúa bajo el candado del carrito: una
    # mutación que llegó antes (otra pestaña) renovó la actividad y gana.
    def self.call(cart)
      expired = false
      ActiveRecord::Base.transaction do
        cart.lock!
        next unless stale?(cart)

        CartInventoryHold.for_cart(cart).delete_all
        cart.update!(status: 'expired', closed_at: Time.current, anonymous_token_digest: nil)
        expired = true
      end
      expired
    end
  end
end
```

- [ ] **Step 5: Run, lint, commit**
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/shopping_carts spec/services/carts spec/models` — Expected: 0 failures.
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/models/shopping_cart.rb app/services/shopping_carts/expire_cart.rb db/migrate/20261011120000_add_expired_status_and_notes_to_shopping_carts.rb`
```bash
git add db/migrate/20261011120000_add_expired_status_and_notes_to_shopping_carts.rb db/schema.rb app/models/shopping_cart.rb app/services/shopping_carts/expire_cart.rb spec/services/shopping_carts/expire_cart_spec.rb spec/factories/shopping_carts.rb
git commit -m "feat: los carritos vencen como 'expired' tras 4 h sin cambios"
```

---

### Task 2: Holds renew with the cart; idle-cart job every 15 min

**Files:**
- Create: `app/jobs/carts/expire_idle_carts_job.rb`, `spec/jobs/carts/expire_idle_carts_job_spec.rb`
- Modify: `app/services/shopping_carts/active_cart_mutation.rb`, `app/models/cart_inventory_hold.rb`, `config/recurring.yml`, `spec/config/recurring_schedule_spec.rb`, `spec/services/carts/hold_cart_lifecycle_spec.rb`

**Interfaces:**
- Consumes: `ExpireCart` (Task 1).
- Produces: `CartInventoryHold.renew_for_cart!(cart) → Integer`; recurring key `carts_expire_idle_every_15_minutes`.

- [ ] **Step 1: Failing specs**

Append inside the top-level describe of `spec/services/carts/hold_cart_lifecycle_spec.rb` (before its final `end`):
```ruby
  describe 'renovación con la actividad del carrito' do
    it 'cualquier cambio renueva los apartados de todo el carrito por 4 horas' do
      stock(count: 1)
      stock(for_product: other, count: 1)
      ShoppingCarts::ActiveCartMutation.add(user: user, product: product, condition: 'brand_new')
      CartInventoryHold.for_cart(cart_for).update_all(expires_at: 30.minutes.from_now)

      ShoppingCarts::ActiveCartMutation.add(user: user, product: other, condition: 'brand_new')

      expect(CartInventoryHold.for_cart(cart_for).pluck(:expires_at)).to all(be > 3.hours.from_now)
    end
  end
```

`spec/jobs/carts/expire_idle_carts_job_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Carts::ExpireIdleCartsJob do
  def cart_with_line(idle_for:)
    item = create(:shopping_cart_item, shopping_cart: create(:shopping_cart, :owned))
    item.shopping_cart.update_columns(last_activity_at: idle_for.ago)
    item.shopping_cart
  end

  it 'vence sólo los carritos con líneas y más de 4 h sin cambios' do
    stale = cart_with_line(idle_for: 5.hours)
    fresh = cart_with_line(idle_for: 1.hour)
    empty = create(:shopping_cart, :owned).tap { |c| c.update_columns(last_activity_at: 5.hours.ago) }

    expect(described_class.perform_now).to eq(1)
    expect(stale.reload.status).to eq('expired')
    expect(fresh.reload.status).to eq('active')
    expect(empty.reload.status).to eq('active')
  end
end
```

`spec/config/recurring_schedule_spec.rb`: in the `contain_exactly(` list add `"carts_expire_idle_every_15_minutes",` after `"carts_expire_inventory_holds_hourly",`, and add:
```ruby
  it "expires idle shopping carts every 15 minutes" do
    expect(production_tasks.fetch("carts_expire_idle_every_15_minutes"))
      .to include("class" => "Carts::ExpireIdleCartsJob", "schedule" => "*/15 * * * *")
  end
```
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/carts/hold_cart_lifecycle_spec.rb spec/jobs/carts spec/config/recurring_schedule_spec.rb` — Expected: FAIL (holds not renewed, job missing, key missing).

- [ ] **Step 2: Implementation**

`app/models/cart_inventory_hold.rb`, after the scopes:
```ruby
  # Renueva por HOLD_DURATION todos los apartados vigentes del carrito, con el
  # reloj de la base: el carrito y sus apartados vencen juntos (ShoppingCart::IDLE_TTL).
  def self.renew_for_cart!(cart)
    active.for_cart(cart).update_all(
      ["expires_at = clock_timestamp() + (? * INTERVAL '1 second'), updated_at = clock_timestamp()",
       HOLD_DURATION.to_i]
    )
  end
```
`app/services/shopping_carts/active_cart_mutation.rb`, in `locked_mutation`, replace
```ruby
        quantity = yield(cart, items)
        cart.update!(last_activity_at: Time.current)
```
with
```ruby
        quantity = yield(cart, items)
        # Cada cambio reinicia las 4 h del carrito y de todos sus apartados.
        CartInventoryHold.renew_for_cart!(cart)
        cart.update!(last_activity_at: Time.current)
```

`app/jobs/carts/expire_idle_carts_job.rb`:
```ruby
# frozen_string_literal: true

module Carts
  # Vence los carritos durables con líneas que llevan ShoppingCart::IDLE_TTL
  # sin cambios, para liberar sus piezas aunque el cliente no regrese. Nunca
  # toca órdenes de venta.
  class ExpireIdleCartsJob < ApplicationJob
    queue_as :default

    def perform
      count = 0
      ShoppingCart.where(status: 'active')
                  .where(last_activity_at: ...ShoppingCart::IDLE_TTL.ago)
                  .where(id: ShoppingCartItem.select(:shopping_cart_id))
                  .find_each { |cart| count += 1 if ShoppingCarts::ExpireCart.call(cart) }
      Rails.logger.info("[Carts::ExpireIdleCartsJob] expired=#{count}")
      count
    end
  end
end
```
`config/recurring.yml` production, right after the `carts_expire_inventory_holds_hourly` entry:
```yaml
  # Carritos sin cambios por 4 h: se vencen y liberan sus piezas apartadas.
  carts_expire_idle_every_15_minutes:
    class: Carts::ExpireIdleCartsJob
    schedule: "*/15 * * * *"
```

- [ ] **Step 3: Run, lint, commit**
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/carts spec/services/shopping_carts spec/jobs/carts spec/config` — Expected: 0 failures.
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/jobs/carts app/models/cart_inventory_hold.rb app/services/shopping_carts/active_cart_mutation.rb`
```bash
git add app/jobs/carts/expire_idle_carts_job.rb spec/jobs/carts/expire_idle_carts_job_spec.rb app/models/cart_inventory_hold.rb app/services/shopping_carts/active_cart_mutation.rb config/recurring.yml spec/config/recurring_schedule_spec.rb spec/services/carts/hold_cart_lifecycle_spec.rb
git commit -m "feat: los apartados se renuevan con el carrito y un job vence carritos inactivos"
```

---

### Task 3: Expire on read (durable + visitor), customer notice, checkout guard

**Files:**
- Create: `app/services/shopping_carts/session_cart_expiry.rb`, `spec/requests/cart_expiry_spec.rb`
- Modify: `app/services/shopping_carts/storefront.rb`, `app/controllers/application_controller.rb`, `app/controllers/checkouts_controller.rb`

**Interfaces:**
- Consumes: `ExpireCart` (Task 1).
- Produces: `Storefront::Persistent#expired?`, `Storefront::Anonymous#expired?`; `ShoppingCarts::SessionCartExpiry::NOTICE`; `SessionCartExpiry.touch!/stale?/clear!`.

- [ ] **Step 1: Failing request spec** — `spec/requests/cart_expiry_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Vencimiento del carrito', type: :request do
  let(:notice) { ShoppingCarts::SessionCartExpiry::NOTICE }
  let(:location) { create(:inventory_location) }
  let(:product) { create(:product, skip_seed_inventory: true, selling_price: 100, minimum_price: 100) }

  before do
    inventory = create(:inventory, product: product, status: :damaged)
    inventory.update_columns(status: Inventory.statuses['available'],
                             item_condition: Inventory.item_conditions['brand_new'],
                             inventory_location_id: location.id)
  end

  context 'cliente con sesión' do
    let(:user) { create(:user) }

    before do
      sign_in user
      post cart_items_path, params: { product_id: product.id }
    end

    def age_cart!(by)
      ShoppingCarts::ActiveCartResolver.find(user).update_columns(last_activity_at: by.ago)
    end

    it 'tras 4 h sin cambios el carrito aparece vacío con el aviso' do
      age_cart!(5.hours)
      get cart_path
      expect(response.body).to include(notice)
      expect(ShoppingCart.where(user: user).pluck(:status)).to eq(['expired'])
      expect(CartInventoryHold.count).to eq(0)
    end

    it 'con actividad reciente no vence ni avisa' do
      age_cart!(3.hours)
      get cart_path
      expect(response.body).not_to include(notice)
      expect(ShoppingCarts::ActiveCartResolver.find(user)).to be_present
    end

    it 'después de vencer, agregar crea un carrito nuevo' do
      age_cart!(5.hours)
      get cart_path
      post cart_items_path, params: { product_id: product.id }
      expect(ShoppingCart.where(user: user).group(:status).count).to eq('expired' => 1, 'active' => 1)
    end

    it 'el checkout no crea orden si el carrito venció y lo explica' do
      age_cart!(5.hours)
      get checkout_step1_path
      expect(response).to redirect_to(cart_path)
      expect(flash[:warning]).to eq(notice)
      expect(SaleOrder.count).to eq(0)
    end
  end

  context 'visitante' do
    it 'el carrito de sesión vence a las 4 h del último cambio' do
      post cart_items_path, params: { product_id: product.id }
      travel 5.hours do
        get cart_path
        expect(response.body).to include(notice)
        expect(response.body).not_to include(product.product_name)
      end
    end

    it 'un carrito de visitante vencido no se importa al iniciar sesión' do
      post cart_items_path, params: { product_id: product.id }
      travel 5.hours do
        sign_in create(:user)
        get cart_path
        expect(ShoppingCartItem.count).to eq(0)
      end
    end
  end
end
```
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/requests/cart_expiry_spec.rb` — Expected: FAIL `uninitialized constant ShoppingCarts::SessionCartExpiry`.

- [ ] **Step 2: SessionCartExpiry** — `app/services/shopping_carts/session_cart_expiry.rb`:
```ruby
# frozen_string_literal: true

module ShoppingCarts
  # Vencimiento del carrito de sesión de un visitante: 4 h después de su último
  # cambio (ShoppingCart::IDLE_TTL), igual que el carrito durable.
  module SessionCartExpiry
    TOUCH_KEY = 'cart_touched_at'
    NOTICE = 'Tu carrito venció tras 4 horas sin actividad y liberamos las piezas apartadas.'

    module_function

    def touch!(session)
      session[TOUCH_KEY] = Time.current.to_i
    end

    # Un carrito sin marca (anterior a este cambio) nunca se considera vencido.
    def stale?(session)
      stamp = session[TOUCH_KEY]
      session[:cart].present? && stamp.present? && Time.zone.at(stamp.to_i) < ShoppingCart::IDLE_TTL.ago
    end

    def clear!(session)
      session[:cart] = {}
      session.delete(TOUCH_KEY)
    end

    # Marca un carrito con líneas que aún no tiene marca, para empezar a contar.
    def stamp_if_missing!(session)
      touch!(session) if session[:cart].present? && session[TOUCH_KEY].blank?
    end
  end
end
```

- [ ] **Step 3: Storefront** — in `app/services/shopping_carts/storefront.rb`:

3a. `class Anonymous` — replace
```ruby
      def cart
        @cart ||= Cart.new(@session)
      end
```
with
```ruby
      def cart
        @cart ||= begin
          expire_if_stale!
          Cart.new(@session)
        end
      end

      def expired?
        cart
        @expired == true
      end
```
and in `add`, `set_quantity` and `remove`, add `SessionCartExpiry.touch!(@session)` right before each `:ok` return line (three places), plus add the private section at the end of `Anonymous`:
```ruby

      private

      def expire_if_stale!
        if SessionCartExpiry.stale?(@session)
          SessionCartExpiry.clear!(@session)
          @expired = true
        else
          SessionCartExpiry.stamp_if_missing!(@session)
        end
      end
```

3b. `class Persistent` — replace
```ruby
      def persistent_cart
        return @persistent_cart if defined?(@persistent_cart)

        @persistent_cart = ActiveCartResolver.find(@user)
      end
```
with
```ruby
      def persistent_cart
        return @persistent_cart if defined?(@persistent_cart)

        cart = ActiveCartResolver.find(@user)
        if cart && ExpireCart.stale?(cart) && ExpireCart.call(cart)
          @expired = true
          # Proyección vacía y sesión ligada: el inicio de sesión nunca vuelve
          # a importar las líneas del carrito vencido.
          SessionProjection.write(@session, nil, {})
          cart = nil
        end
        @persistent_cart = cart
      end

      def expired?
        cart
        @expired == true
      end
```
and in `bind_session!`, as its first line, add:
```ruby
        if SessionCartExpiry.stale?(@session)
          SessionCartExpiry.clear!(@session)
          @expired = true
        end
```

- [ ] **Step 4: Notice + checkout guard**

`app/controllers/application_controller.rb`: after `before_action :set_locale` add
```ruby
  before_action :notify_expired_cart, if: :storefront_request?
```
and in the `protected` section add:
```ruby
  # Avisa una sola vez, en la página que el cliente esté viendo, que su carrito
  # venció (ShoppingCarts::ExpireCart / SessionCartExpiry).
  def notify_expired_cart
    flash.now[:warning] = ShoppingCarts::SessionCartExpiry::NOTICE if storefront_cart.expired?
  end

  def storefront_request?
    (request.format.html? || request.format.turbo_stream?) &&
      !controller_path.start_with?('admin/', 'api/') &&
      !devise_controller?
  end
```
`app/controllers/checkouts_controller.rb`: replace
```ruby
  def set_cart
    @cart = current_cart
  end
```
with
```ruby
  def set_cart
    @cart = current_cart
    return unless storefront_cart.expired?

    redirect_to cart_path, flash: { warning: ShoppingCarts::SessionCartExpiry::NOTICE }
  end
```
Check: `grep -n "warning" app/views/layouts/_flash.html.erb` — if `:warning` is not rendered, add it to the flash partial with the same markup as `:alert` (Bootstrap `alert-warning`).

- [ ] **Step 5: Run, lint, commit**
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/requests/cart_expiry_spec.rb spec/requests spec/services/shopping_carts spec/services/carts` — Expected: 0 failures (allow the known order-dependent `inventory_locations_spec.rb:39` only if it also fails on `main` in isolation; the full suite in Task 6 is the arbiter).
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/services/shopping_carts app/controllers/application_controller.rb app/controllers/checkouts_controller.rb`
```bash
git add app/services/shopping_carts/session_cart_expiry.rb app/services/shopping_carts/storefront.rb app/controllers/application_controller.rb app/controllers/checkouts_controller.rb app/views/layouts/_flash.html.erb spec/requests/cart_expiry_spec.rb
git commit -m "feat: el carrito vencido se vacía con aviso, también para visitantes y en el checkout"
```

---

### Task 4: Order alerts (read-only) — page and dashboard

**Files:**
- Create: `app/services/sale_orders/alerts.rb`, `app/controllers/admin/order_alerts_controller.rb`, `app/views/admin/order_alerts/index.html.erb`, `spec/services/sale_orders/alerts_spec.rb`, `spec/requests/admin/order_alerts_spec.rb`
- Modify: `config/routes.rb` (admin namespace), `app/views/admin/partials/_sidebar.html.erb`, `app/controllers/admin/dashboard_controller.rb` (`load_alerts`)

**Interfaces:**
- Produces: `SaleOrders::Alerts.stale_pending / .overpaid / .inconsistent → ActiveRecord::Relation` (rows respond to `paid_amount`, `held_units`), `.counts → { stale_pending:, overpaid:, inconsistent: }`; `admin_order_alerts_path`.

- [ ] **Step 1: Failing specs**

`spec/services/sale_orders/alerts_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SaleOrders::Alerts do
  def order(status: 'Pending', age: 40.days, total: 100)
    # Se crea normal y luego se fija el estado: "Canceled" sólo se alcanza por
    # SaleOrders::CancelOrderService, así que no se pasa al crear.
    create(:sale_order).tap do |o|
      o.update_columns(status: status, created_at: age.ago, total_order_value: total)
    end
  end

  def pay(order, amount, status: 'Completed')
    Payment.insert_all!([{ sale_order_id: order.id, amount: amount, status: status, payment_method: 2,
                           created_at: Time.current, updated_at: Time.current }])
  end

  def unit(order, status)
    create(:inventory, product: create(:product, skip_seed_inventory: true), status: :damaged)
      .tap { |i| i.update_columns(status: Inventory.statuses[status], sale_order_id: order.id) }
  end

  it 'lista órdenes Pending de más de 30 días con lo abonado y las unidades retenidas' do
    old = order
    pay(old, 30)
    unit(old, 'reserved')
    unit(old, 'reserved')
    order(age: 10.days)

    rows = described_class.stale_pending.to_a
    expect(rows.map(&:id)).to eq([old.id])
    expect(rows.first.paid_amount.to_d).to eq(30)
    expect(rows.first.held_units).to eq(2)
  end

  it 'lista órdenes no canceladas con pagos completados mayores al total' do
    over = order(status: 'Delivered', total: 100)
    pay(over, 150)
    pending_payment = order(status: 'Delivered', total: 100)
    pay(pending_payment, 150, status: 'Pending')
    exact = order(status: 'Delivered', total: 100)
    pay(exact, 100.005)
    canceled = order(status: 'Canceled', total: 100)
    pay(canceled, 150)

    expect(described_class.overpaid.map(&:id)).to eq([over.id])
  end

  it 'lista órdenes Pending con unidades ya vendidas' do
    bad = order(age: 1.day)
    unit(bad, 'sold')
    fine = order(age: 1.day)
    unit(fine, 'reserved')

    expect(described_class.inconsistent.map(&:id)).to eq([bad.id])
  end

  it 'cuenta las tres alertas' do
    order
    expect(described_class.counts).to eq(stale_pending: 1, overpaid: 0, inconsistent: 0)
  end
end
```

`spec/requests/admin/order_alerts_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin alertas de órdenes', type: :request do
  it 'muestra cada sección con enlace a la orden y no modifica nada' do
    sign_in create(:user, :admin)
    old = create(:sale_order, status: 'Pending').tap { |o| o.update_columns(created_at: 40.days.ago) }

    expect { get admin_order_alerts_path }.not_to(change { SaleOrder.pluck(:id, :status, :updated_at) })
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Alertas de órdenes', old.id, admin_sale_order_path(old))
  end

  it 'no deja entrar a un cliente' do
    sign_in create(:user)
    get admin_order_alerts_path
    expect(response).to redirect_to(root_path)
  end

  it 'el dashboard avisa cuando hay órdenes que atender' do
    sign_in create(:user, :admin)
    create(:sale_order, status: 'Pending').tap { |o| o.update_columns(created_at: 40.days.ago) }
    get admin_dashboard_path
    expect(response.body).to include('requieren atención', admin_order_alerts_path)
  end
end
```
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/sale_orders/alerts_spec.rb spec/requests/admin/order_alerts_spec.rb` — Expected: FAIL (`uninitialized constant SaleOrders::Alerts`, missing route).

- [ ] **Step 2: Query** — `app/services/sale_orders/alerts.rb`:
```ruby
# frozen_string_literal: true

module SaleOrders
  # Órdenes que requieren atención manual. Sólo lectura: nada aquí cancela,
  # cobra ni corrige una orden. Todo se agrega en SQL (el dyno tiene 512 MB).
  module Alerts
    STALE_PENDING_AFTER = 30.days
    TOLERANCE = 0.01

    module_function

    def paid_sql
      "COALESCE((SELECT SUM(p.amount) FROM payments p " \
        "WHERE p.sale_order_id = sale_orders.id AND p.status = 'Completed'), 0)"
    end

    def held_sql
      statuses = Inventory.statuses.values_at('reserved', 'pre_reserved', 'sold').join(', ')
      "(SELECT COUNT(*) FROM inventories i WHERE i.sale_order_id = sale_orders.id AND i.status IN (#{statuses}))"
    end

    def with_figures(scope)
      scope.select("sale_orders.*, #{paid_sql} AS paid_amount, #{held_sql} AS held_units").includes(:user)
    end

    def stale_pending
      with_figures(SaleOrder.where(status: 'Pending').where(created_at: ...STALE_PENDING_AFTER.ago))
        .order(:created_at)
    end

    def overpaid
      with_figures(SaleOrder.where.not(status: 'Canceled').where("#{paid_sql} > sale_orders.total_order_value + #{TOLERANCE}"))
        .order(Arel.sql("#{paid_sql} - sale_orders.total_order_value DESC"))
    end

    def inconsistent
      sold = Inventory.statuses.fetch('sold')
      with_figures(SaleOrder.where(status: 'Pending')
                            .where("EXISTS (SELECT 1 FROM inventories i WHERE i.sale_order_id = sale_orders.id AND i.status = #{sold})"))
        .order(:created_at)
    end

    def counts
      {
        stale_pending: SaleOrder.where(status: 'Pending').where(created_at: ...STALE_PENDING_AFTER.ago).count,
        overpaid: SaleOrder.where.not(status: 'Canceled').where("#{paid_sql} > sale_orders.total_order_value + #{TOLERANCE}").count,
        inconsistent: SaleOrder.where(status: 'Pending')
                               .where("EXISTS (SELECT 1 FROM inventories i WHERE i.sale_order_id = sale_orders.id AND i.status = #{Inventory.statuses.fetch('sold')})")
                               .count
      }
    end
  end
end
```

- [ ] **Step 3: Controller, route, view, sidebar, dashboard**

`config/routes.rb`, inside `namespace :admin do`, right after `resources :sale_orders do … end` block's line (anywhere in the namespace):
```ruby
    get 'order_alerts', to: 'order_alerts#index', as: :order_alerts
```
`app/controllers/admin/order_alerts_controller.rb`:
```ruby
# frozen_string_literal: true

module Admin
  # Órdenes que requieren atención manual (ver SaleOrders::Alerts). Sólo lectura.
  class OrderAlertsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    def index
      @stale_pending = SaleOrders::Alerts.stale_pending
      @overpaid = SaleOrders::Alerts.overpaid
      @inconsistent = SaleOrders::Alerts.inconsistent
    end
  end
end
```
`app/views/admin/order_alerts/index.html.erb`:
```erb
<% content_for :title, 'Alertas de órdenes' %>
<h1 class="h3 mb-1"><i class="fa-solid fa-triangle-exclamation text-warning"></i> Alertas de órdenes</h1>
<p class="text-muted mb-4">Órdenes que requieren tu atención. Nada aquí se cambia solo: abre cada orden para cobrarla, cancelarla o corregirla.</p>

<% sections = [
     [:stale_pending, "Sin pagar con más de #{SaleOrders::Alerts::STALE_PENDING_AFTER.in_days.to_i} días", @stale_pending,
      'Pending: cobra, cancela o mantenla como apartado. Sus unidades siguen retenidas.'],
     [:overpaid, 'Pagos mayores al total', @overpaid, 'El pago completado supera el total de la orden.'],
     [:inconsistent, 'Estados inconsistentes', @inconsistent, 'Pending con unidades ya marcadas como vendidas.']
   ] %>
<% sections.each do |key, title, rows, help| %>
  <div class="card mb-4" id="alertas-<%= key %>">
    <div class="card-header d-flex justify-content-between align-items-center">
      <strong><%= title %></strong>
      <span class="badge <%= rows.size.positive? ? 'bg-warning text-dark' : 'bg-success' %>"><%= rows.size %></span>
    </div>
    <div class="card-body p-0">
      <p class="small text-muted px-3 pt-2 mb-2"><%= help %></p>
      <% if rows.empty? %>
        <p class="px-3 pb-3 mb-0 text-success">Nada pendiente.</p>
      <% else %>
        <div class="table-responsive">
          <table class="table table-sm table-hover mb-0 align-middle">
            <thead><tr>
              <th>Orden</th><th>Cliente</th><th>Fecha</th><th class="text-end">Días</th><th>Estado</th>
              <th class="text-end">Total</th><th class="text-end">Pagado</th><th class="text-end">Saldo</th>
              <th class="text-end">Unidades</th><th>Notas</th>
            </tr></thead>
            <tbody>
              <% rows.each do |o| %>
                <% paid = o.paid_amount.to_d %>
                <tr>
                  <td><%= link_to o.id, admin_sale_order_path(o) %></td>
                  <td><%= o.user&.name.presence || o.user&.email %></td>
                  <td><%= l(o.created_at.to_date) %></td>
                  <td class="text-end"><%= (Date.current - o.created_at.to_date).to_i %></td>
                  <td><%= o.status %></td>
                  <td class="text-end"><%= number_to_currency(o.total_order_value) %></td>
                  <td class="text-end"><%= number_to_currency(paid) %></td>
                  <td class="text-end <%= 'text-danger' if paid > o.total_order_value.to_d %>"><%= number_to_currency(o.total_order_value.to_d - paid) %></td>
                  <td class="text-end"><%= o.held_units %></td>
                  <td class="small text-muted"><%= truncate(o.notes.to_s, length: 60) %></td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      <% end %>
    </div>
  </div>
<% end %>
```
`app/views/admin/partials/_sidebar.html.erb`: right after the `'Órdenes de Venta'` `<li>` block add:
```erb
      <li class="nav-item px-2">
        <%= admin_sidebar_link 'Alertas de órdenes', admin_order_alerts_path, icon: 'triangle-exclamation', section: true %>
      </li>
```
`app/controllers/admin/dashboard_controller.rb`, in `load_alerts`, right after `@alerts = []`:
```ruby

      # Órdenes que requieren atención manual (sin pagar >30 días, pagadas de más, inconsistentes).
      order_alerts = SaleOrders::Alerts.counts.values.sum
      if order_alerts.positive?
        @alerts << {
          type: 'warning',
          icon: 'fa-triangle-exclamation',
          message: "#{order_alerts} órdenes requieren atención",
          link: admin_order_alerts_path,
          link_text: 'Ver alertas'
        }
      end
```
If `User#name` does not exist, use the attribute the admin sale order views use for the customer (`grep -n "user\." app/views/admin/sale_orders/index.html.erb | head -3`) and record the deviation.

- [ ] **Step 4: Run, lint, commit**
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/sale_orders/alerts_spec.rb spec/requests/admin/order_alerts_spec.rb spec/requests/admin` — Expected: 0 failures (same `inventory_locations_spec.rb:39` caveat as Task 3).
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/services/sale_orders/alerts.rb app/controllers/admin/order_alerts_controller.rb app/controllers/admin/dashboard_controller.rb config/routes.rb`
```bash
git add app/services/sale_orders/alerts.rb app/controllers/admin/order_alerts_controller.rb app/views/admin/order_alerts/index.html.erb config/routes.rb app/views/admin/partials/_sidebar.html.erb app/controllers/admin/dashboard_controller.rb spec/services/sale_orders/alerts_spec.rb spec/requests/admin/order_alerts_spec.rb
git commit -m "feat: alertas de órdenes sin pagar, pagadas de más e inconsistentes (sólo lectura)"
```

---

### Task 5: Checkout notes on the durable cart; cart shows "Envío desde $X"

**Files:**
- Modify: `app/helpers/checkout_session_helper.rb`, `app/controllers/checkouts_controller.rb`, `app/views/checkouts/step1.html.erb`, `app/services/shipping/calculator.rb`, `app/views/carts/show.html.erb`, `app/models/cart.rb`
- Test: `spec/requests/checkout_notes_spec.rb`, `spec/requests/cart_shipping_estimate_spec.rb`

**Interfaces:**
- Consumes: `shopping_carts.checkout_notes` (Task 1).
- Produces: `CheckoutSessionHelper::MAX_NOTES = 1000`; `Shipping::Calculator.cheapest_active_rate → BigDecimal|nil`.

- [ ] **Step 1: Failing specs**

`spec/requests/checkout_notes_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Notas del checkout', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
    product = create(:product, selling_price: 100, minimum_price: 100)
    post cart_items_path, params: { product_id: product.id }
  end

  it 'acepta notas largas sin romper la sesión y guarda 1000 caracteres en el carrito' do
    post checkout_step1_path, params: { notes: 'x' * 5000 }
    expect(response).to redirect_to(checkout_step2_path)
    expect(ShoppingCarts::ActiveCartResolver.find(user).checkout_notes.length).to eq(1000)
    expect(session.to_h.keys).not_to include('checkout_notes')
  end

  it 'el campo limita a 1000 caracteres' do
    get checkout_step1_path
    expect(response.body).to match(/<textarea[^>]*maxlength="1000"/)
  end
end
```
`spec/requests/cart_shipping_estimate_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Envío estimado en el carrito', type: :request do
  before do
    ShippingMethod.delete_all
    create(:shipping_method, code: 'envio_estandar', base_cost: 60, active: true)
    create(:shipping_method, code: 'envio_express', base_cost: 180, active: true)
    product = create(:product, selling_price: 100, minimum_price: 100)
    post cart_items_path, params: { product_id: product.id }
  end

  it 'muestra el envío desde la tarifa activa más barata' do
    allow(Shipping::Calculator).to receive(:free_shipping?).and_return(false)
    get cart_path
    expect(response.body).to include('desde $60')
  end

  it 'muestra envío gratis cuando aplica' do
    allow(Shipping::Calculator).to receive(:free_shipping?).and_return(true)
    get cart_path
    expect(response.body).to include('¡Gratis!')
  end
end
```
If no `:shipping_method` factory exists (`ls spec/factories | grep -i shipping`), create the records with `ShippingMethod.create!(code:, name:, base_cost:, active: true)` using the model's required attributes (`grep -n validates app/models/shipping_method.rb`) — record the deviation.
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/requests/checkout_notes_spec.rb spec/requests/cart_shipping_estimate_spec.rb` — Expected: FAIL (CookieOverflow / missing text).

- [ ] **Step 2: Notes on the cart**
`app/helpers/checkout_session_helper.rb`:
- remove `checkout_notes: 'checkout_notes',` from `SESSION_KEYS`;
- add `MAX_NOTES = 1000` below `SESSION_KEYS`;
- replace the `checkout_notes` and `set_checkout_notes` methods with:
```ruby
  # Las notas viven en el carrito durable, no en la cookie de sesión (4 KB):
  # unas notas largas rompían el checkout con CookieOverflow. El checkout
  # siempre exige sesión iniciada, así que el carrito durable existe.
  def checkout_notes
    storefront_cart.persistent_cart&.checkout_notes
  end

  def set_checkout_notes(notes)
    storefront_cart.persistent_cart&.update_column(:checkout_notes, notes.to_s.strip.first(MAX_NOTES).presence)
  end
```
- in `clear_checkout_session!` remove `session.delete(SESSION_KEYS[:checkout_notes])`.
`app/views/checkouts/step1.html.erb`: replace
```erb
<%= text_area_tag :notes, nil, rows: 2, class: "form-control", placeholder: "Instrucciones especiales, comentarios sobre tu pedido..." %>
```
with
```erb
<%= label_tag :notes, 'Notas del pedido (opcional)', class: 'form-label small text-muted' %>
<%= text_area_tag :notes, checkout_notes, rows: 2, maxlength: CheckoutSessionHelper::MAX_NOTES, class: "form-control", placeholder: "Instrucciones especiales, comentarios sobre tu pedido..." %>
```
(If `checkout_notes` is not available in the view, add `helper_method :checkout_notes` in `CheckoutsController`.)

- [ ] **Step 3: Shipping estimate**
`app/services/shipping/calculator.rb`, next to `free_shipping?`:
```ruby
      # La tarifa activa más barata, para el "envío desde" del carrito.
      def cheapest_active_rate
        ShippingMethod.active.where.not(base_cost: nil).minimum(:base_cost)&.to_d
      end
```
`app/views/carts/show.html.erb`: replace
```erb
<li class="d-flex justify-content-between text-muted"><span>Envío</span><span id="summary-shipping" class="small">A calcular</span></li>
```
with
```erb
<% cheapest = Shipping::Calculator.cheapest_active_rate %>
<li class="d-flex justify-content-between text-muted"><span>Envío</span><span id="summary-shipping" class="small">
  <% if @cart.free_shipping_eligible? %>¡Gratis!<% elsif cheapest %>desde <%= number_to_currency(cheapest, precision: 0) %><% else %>A calcular<% end %>
</span></li>
```
`app/models/cart.rb`: delete `SHIPPING_FLAT = 99`, the `shipping_cost` method (with its two comment lines) and `grand_total`. Keep `free_shipping_eligible?`. Then `grep -rn "SHIPPING_FLAT\|grand_total\|cart.*shipping_cost" app spec` must show no cart usages.

- [ ] **Step 4: Run, lint, commit**
Run: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/requests spec/models spec/services/shipping` — Expected: 0 failures (same caveat).
Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/helpers/checkout_session_helper.rb app/services/shipping/calculator.rb app/models/cart.rb app/controllers/checkouts_controller.rb`
```bash
git add app/helpers/checkout_session_helper.rb app/controllers/checkouts_controller.rb app/views/checkouts/step1.html.erb app/services/shipping/calculator.rb app/views/carts/show.html.erb app/models/cart.rb spec/requests/checkout_notes_spec.rb spec/requests/cart_shipping_estimate_spec.rb
git commit -m "fix: las notas del checkout ya no viven en la cookie y el carrito muestra el envío desde la tarifa más barata"
```

---

### Task 6: Full verification

- [ ] `npm run build && RUN_SYSTEM_SPECS=1 RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bundle exec rspec` — Expected: 0 failures. Hands off until it exits.
- [ ] `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app config/routes.rb db/migrate/20261011120000_add_expired_status_and_notes_to_shopping_carts.rb` — Expected: no offenses.
- [ ] `graphify update .`
- [ ] After merge + `git push heroku main` (release phase runs the migration): `heroku run --no-tty -- bin/rails runner 'p SaleOrders::Alerts.counts; p ShoppingCart.group(:status).count'` — expected roughly `{stale_pending: 29, overpaid: 39, inconsistent: 1}`; the admin opens `/admin/order_alerts`.
