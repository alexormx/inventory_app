# Página Finanzas mensual — plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Página admin `/admin/finances` con estado de resultados y flujo de caja por mes (o por año en "Todo el histórico"), saldos al cierre y descarga CSV.

**Architecture:** Un servicio de SQL puro reconoce cada venta en su *fecha de conclusión* (el pago que completa el total). Otros dos servicios agregan, también en SQL, los flujos por periodo y los saldos al cierre. `Finance::MonthlyStatement` los compone en una estructura que consumen una vista ERB y un generador CSV. Nada carga órdenes ni piezas en memoria.

**Tech Stack:** Rails 7 / PostgreSQL (funciones de ventana), ERB + Bootstrap con el layout `admin`, RSpec + FactoryBot.

**Spec:** `docs/superpowers/specs/2026-11-07-finanzas-mensual-design.md`. Léelo antes de cada tarea: las definiciones de cada fila viven ahí.

## Global Constraints

- Ruby siempre con `~/.rvm/bin/rvm 3.2.3 do ...` (el `bundle` y el `bin/rails` sueltos usan Ruby 2.7).
- Postgres local puede estar apagado: si `rspec` no conecta, pide al usuario `! sudo service postgresql start`.
- Base de prueba: `RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bin/rails db:test:prepare`. **Nunca** `db:prepare`, `db:drop`, `db:reset`, `db:schema:load` ni `db:setup`. `bin/rails db:migrate` contra desarrollo sí está permitido.
- Producción es un dyno de 512 MB: cada consulta devuelve totales agregados (una fila por periodo), nunca registros individuales.
- Zona horaria de la app: `Time.zone` (hoy UTC, `config.time_zone` comentado). Los límites de mes usan `Time.zone`; no se cambia la configuración.
- Sólo admin: el mismo `authorize_admin!` que `Admin::DashboardController` (redirige a `root_path` con `alert: 'Not authorized.'`).
- Textos visibles en español. No exponer `product_sku` ni `supplier_product_code` (la página no muestra productos).
- Estados de pago "recibido": `%w[Completed Refunded]` (mismo valor que `SaleOrders::CancelOrderService::RECEIVED_PAYMENT_STATUSES`).
- Las órdenes con estado `Canceled` o `Returned` nunca se reconocen como venta.
- Los callbacks recalculan los totales (`SaleOrder#compute_financials`, `PurchaseOrder#recalculate_totals`). En los specs, fija `total_order_value`, `total_cost_mxn` y `total_order_cost` con `update_columns` después de crear.
- Después de cambiar código: `graphify update .`.
- RuboCop no revisa `spec/**` ni `lib/tasks/**`; corre `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app config db/migrate` sólo sobre archivos de app.

## Review Focus

1. **Parámetro `year` raro** (`abc`, `1900`, `3000`, vacío): la página debe responder 200 con el año acotado a `[first_year, today.year]`, no 500. *Test en la Tarea 5.*
2. **Base sin ninguna operación:** la página y el CSV se generan con el año en curso y todo en cero; el margen queda vacío (sin división entre cero). *Test en la Tarea 4.*
3. **Mes con reembolsos pero sin ventas:** margen `nil` y utilidad negativa, sin error. *Test en la Tarea 4.*
4. **Pago `Completed` sin `paid_at`** (datos viejos): se ignora en cobros y en conclusión, sin error. *Test en la Tarea 2.*
5. **Orden sobrepagada o con pagos que suman exactamente el total en dos meses:** la conclusión cae en el pago que cruza el total, y un pago extra posterior no la mueve. *Test en la Tarea 2.*

---

### Task 1: Fecha de reembolso en pagos

**Files:**
- Create: `db/migrate/20261107010000_add_refunded_at_to_payments.rb`
- Modify: `app/models/payment.rb`, `db/schema.rb` (generado)
- Test: `spec/models/payment_refunded_at_spec.rb`

**Interfaces:**
- Produces: columna `payments.refunded_at :date` (nullable, con índice) que llenan el callback y el backfill.

- [ ] **Step 1: Write the failing test**

```ruby
RSpec.describe Payment, 'refunded_at' do
  let(:payment) { create(:payment, status: 'Completed', amount: 100) }

  it 'fija refunded_at con la fecha de hoy al pasar a Refunded' do
    travel_to(Time.zone.local(2026, 3, 31, 12)) { payment.update!(status: 'Refunded') }
    expect(payment.reload.refunded_at).to eq(Date.new(2026, 3, 31))
  end

  it 'no sobrescribe un refunded_at existente' do
    payment.update!(status: 'Refunded', refunded_at: Date.new(2026, 1, 5))
    payment.update!(amount: 90)
    expect(payment.reload.refunded_at).to eq(Date.new(2026, 1, 5))
  end

  it 'deja refunded_at vacío en pagos no reembolsados' do
    expect(payment.refunded_at).to be_nil
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/models/payment_refunded_at_spec.rb`
Expected: FAIL (`unknown attribute 'refunded_at'` / `NoMethodError`)

- [ ] **Step 3: Write the migration**

`add_column :payments, :refunded_at, :date` + `add_index :payments, :refunded_at`. En `up`, el backfill en SQL:
`UPDATE payments SET refunded_at = (updated_at AT TIME ZONE 'UTC' AT TIME ZONE '<tz>')::date WHERE status = 'Refunded' AND refunded_at IS NULL`, con `<tz>` = `Time.zone.tzinfo.name` citado con `connection.quote`. `down` quita el índice y la columna. Usa `up`/`down` explícitos.

- [ ] **Step 4: Add the callback in `app/models/payment.rb`**

`before_save :set_refunded_at_if_refunded`, privado: `self.refunded_at ||= Time.zone.today if status == 'Refunded'`. Junto a `set_paid_at_if_completed`. Esto cubre `MercadoPago::SyncPayment`, que usa `payment.update!`.

- [ ] **Step 5: Migrate and prepare the test DB**

Run: `~/.rvm/bin/rvm 3.2.3 do bin/rails db:migrate && RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bin/rails db:test:prepare`
Expected: `db/schema.rb` muestra `t.date "refunded_at"` en `payments`.

- [ ] **Step 6: Run test to verify it passes**

Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/models/payment_refunded_at_spec.rb spec/models/payment_spec.rb`
Expected: PASS (si `payment_spec.rb` no existe, sólo el primero)

- [ ] **Step 7: Commit**

```bash
git add db/migrate/20261107010000_add_refunded_at_to_payments.rb db/schema.rb app/models/payment.rb spec/models/payment_refunded_at_spec.rb
git commit -m "feat(payments): registrar la fecha de reembolso"
```

---

### Task 2: Reconocimiento de venta (fecha de conclusión)

**Files:**
- Create: `app/services/finance/sale_recognition.rb`
- Test: `spec/services/finance/sale_recognition_spec.rb`

**Interfaces:**
- Produces: `Finance::SaleRecognition.sql -> String`. Es un `SELECT` sin punto y coma que devuelve una fila por orden reconocida, con columnas `sale_order_id` (string) y `concluded_on` (date). Las tareas siguientes lo usan como subconsulta: `JOIN (#{Finance::SaleRecognition.sql}) rec ON rec.sale_order_id = sale_orders.id`.
- Produces: `Finance::SaleRecognition.concluded_on_by_order -> Hash{String => Date}` (sólo para specs y depuración).
- Produces: `Finance::RECEIVED_PAYMENT_STATUSES = %w[Completed Refunded].freeze` en `app/services/finance/sale_recognition.rb`, o en `app/services/finance.rb` si Zeitwerk lo exige.

Reglas (spec, "Fecha de conclusión de una venta"):
1. Pagos recibidos con `paid_at IS NOT NULL`. Suma acumulada `SUM(amount) OVER (PARTITION BY sale_order_id ORDER BY paid_at, id ROWS UNBOUNDED PRECEDING)`.
2. `concluded_on` = el `MIN(paid_at)` donde la suma acumulada `>= total_order_value`.
3. Se excluyen órdenes con `status IN ('Canceled','Returned')`. Cualquier otro estado vale, **incluido `Pending`**.
4. Respaldo: una orden con estado en `SaleOrder::ACTIVE_SALE_STATUSES`, **sin ningún** pago recibido, y con `NOT (users.credit_enabled OR sale_orders.credit_override)`, usa `concluded_on = order_date`.

- [ ] **Step 1: Write the failing tests** (`concluded_on_by_order[order.id]`)

```ruby
it 'anticipo en marzo y liquidación en junio → concluye en junio'      # pagos 40 (2026-03-10) + 60 (2026-06-02), total 100 → 2026-06-02
it 'no concluye mientras falta pagar'                                   # status Pending, pago 40 de 100 → nil
it 'pago extra posterior no mueve la conclusión'                        # 100 (03-01) + 20 (05-01), total 100 → 2026-03-01
it 'un reembolso posterior no la des-concluye'                          # pago 100 Completed→Refunded, orden regresa a Pending → 2026-03-01
it 'ignora pagos sin paid_at'                                           # pago Completed con update_columns(paid_at: nil) → nil
it 'excluye canceladas y devueltas'                                     # pagada completa, status Canceled / Returned → nil
it 'orden antigua sin pagos cuenta en su order_date'                    # Delivered, order_date 2024-05-01, sin pagos → 2024-05-01
it 'orden a crédito sin liquidar no se reconoce'                        # user credit_enabled, Delivered, sin pagos → nil
it 'orden con pago parcial no usa el respaldo'                          # Delivered, pago 40 de 100 → nil
```

Arma cada orden con `create(:sale_order, ...)` y `update_columns(total_order_value: 100, status: ...)`. Crea los pagos con `create(:payment, sale_order:, amount:, status: 'Completed')` y `update_columns(paid_at:)`, para no depender de `travel_to` ni de `update_status_if_fully_paid!`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/finance/sale_recognition_spec.rb`
Expected: FAIL (`uninitialized constant Finance::SaleRecognition`)

- [ ] **Step 3: Implement `Finance::SaleRecognition`** como `module_function`. Arma `sql` con un CTE de pagos recibidos, un `UNION ALL` del respaldo y los literales citados con `connection.quote`. `concluded_on_by_order` ejecuta `select_rows` sobre `sql`.

- [ ] **Step 4: Run tests to verify they pass**

Run: el mismo comando del Step 2. Expected: 9 examples, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add app/services/finance/sale_recognition.rb spec/services/finance/sale_recognition_spec.rb
git commit -m "feat(finanzas): fecha de conclusión de cada venta"
```

---

### Task 3: Flujos por periodo y saldos al cierre

**Files:**
- Create: `app/services/finance/period_flows.rb`, `app/services/finance/closing_balances.rb`
- Test: `spec/services/finance/period_flows_spec.rb`, `spec/services/finance/closing_balances_spec.rb`

**Interfaces:**
- Consumes: `Finance::SaleRecognition.sql`, `Finance::RECEIVED_PAYMENT_STATUSES`.
- Produces: `Finance::PeriodFlows.new(range: Range<Date>, grain: :month | :year).call -> Hash{Date => Hash{Symbol => BigDecimal|Integer}}`. La llave es el inicio del periodo (`DATE_TRUNC`) y sólo aparecen periodos con datos. Las llaves internas son `:sales`, `:sales_count`, `:discounts`, `:sale_refunds`, `:cogs`, `:cash_in`, `:purchases`, `:refunds`.
- Produces: `Finance::ClosingBalances.new(dates: Array<Date>).call -> Hash{Date => {advances: BigDecimal, inventory: BigDecimal}}`, con una entrada por cada fecha pedida.
- Produces: `Finance::ClosingBalances.inventory_movements_sql -> String`. Devuelve filas `(purchase_cost, entered_on date, exited_on date|null)`. Lo usa `first_operation_on` en la Tarea 4.

Definiciones exactas: tablas "Filas" y "Reconstrucción del inventario a costo" del spec. Resumen:
- `sales`/`discounts`/`cogs`/`sales_count`: órdenes con `rec.concluded_on` en el periodo. `LINE_REVENUE_SQL` y `LINE_COGS_SQL` (con `JOIN products`) por línea; `discount` por orden, en una consulta separada para no multiplicarlo por línea.
- `sale_refunds`: pagos `Refunded` con `refunded_at` en el periodo cuya orden tiene `rec.concluded_on <= refunded_at`.
- `refunds`: todos los pagos `Refunded` con `refunded_at` en el periodo.
- `cash_in`: pagos recibidos con `paid_at` en el periodo.
- `purchases`: `purchase_orders` con `status <> 'Canceled'` por `order_date`, `COALESCE(NULLIF(total_cost_mxn,0), total_order_cost)`, más inventario con `purchase_order_id IS NULL AND purchase_order_item_id IS NULL AND purchase_cost > 0` agrupado por la fecha de `created_at` en `Time.zone`.
- Inventario: `entered_on` = `purchase_orders.order_date` si tiene `purchase_order_id` (PO no cancelada); si no, la fecha de `created_at`. `exited_on` = el menor entre: `rec.concluded_on` de su `sale_order_id`; la fecha de `status_changed_at` si su estado es `damaged`/`lost`/`scrap`/`marketing`; la fecha de `status_changed_at` si es `sold`/`pre_sold` con `sale_order_id IS NULL`. Cuenta al cierre D si `entered_on <= D AND (exited_on IS NULL OR exited_on > D)`. Usa los enteros de `Inventory.statuses`.
- `advances` al cierre D: pagos recibidos con `paid_at <= D`, sin contar los `Refunded` con `refunded_at <= D`, de órdenes con `status <> 'Returned'` y (`rec.concluded_on IS NULL OR rec.concluded_on > D`). Usa `LEFT JOIN` a `rec`.
- Para varias fechas, `ClosingBalances` usa una sola consulta por concepto con `unnest(ARRAY[...]::date[]) AS d(on)` y `GROUP BY d.on`.

- [ ] **Step 1: Write the failing tests — `PeriodFlows`** (`grain: :month`, rango 2026-01-01..2026-12-31)

```ruby
it 'cuenta la venta en el mes de conclusión, no en order_date'   # order_date 03-05, pagos 40 (03-10) + 60 (06-02), línea 100 costo 60
  # flows[Date.new(2026,3,1)][:cash_in] == 40; flows[Date.new(2026,6,1)] incluye sales: 100, cogs: 60, cash_in: 60, sales_count: 1
  # flows[Date.new(2026,3,1)][:sales] es nil o 0
it 'descuento de orden no se multiplica por líneas'               # 2 líneas, discount 10 → discounts == 10
it 'reembolso resta en el mes del reembolso y no toca el original' # concluida en 03, reembolso 30 con refunded_at 05-15
  # marzo: sales 100, cash_in 100; mayo: sale_refunds 30, refunds 30
it 'reembolso de anticipo no concluido sólo cuenta como flujo'     # pago 40, Refunded en 04 → abril refunds 40, sale_refunds 0
it 'compras: por fila usa total_order_cost cuando total_cost_mxn es 0, excluye canceladas'
  # PO A total_cost_mxn 500; PO B total_cost_mxn 0 / total_order_cost 300; PO C Canceled 999 → purchases == 800
it 'altas manuales cuentan; piezas con purchase_order_id no'      # inventario manual 150 + pieza con purchase_order_id sin item 70 → +150
it 'agrupa por año con grain: :year'
```

- [ ] **Step 2: Write the failing tests — `ClosingBalances`**

```ruby
it 'anticipo por entregar hasta que la venta concluye'            # pago 40 (03-10) sobre total 100, liquidada 06-02
  # advances al 2026-03-31 == 40, al 2026-05-31 == 40, al 2026-06-30 == 0
it 'anticipo reembolsado deja de contar desde su refunded_at'
it 'orden cancelada con pago no reembolsado sigue como anticipo'
it 'inventario: entra por order_date de la PO y sale al concluir su venta'
  # pieza costo 80 de PO con order_date 02-01, ligada a orden concluida 04-10
  # inventory al 01-31 == 0, al 02-28 == 80, al 04-30 == 0
it 'inventario: pieza dañada sale en status_changed_at; sold sin orden también'
it 'devuelve una entrada por cada fecha aunque no haya datos'     # call con dates [d1, d2] sobre base vacía → ambos {advances: 0, inventory: 0}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/finance/period_flows_spec.rb spec/services/finance/closing_balances_spec.rb`
Expected: FAIL (`uninitialized constant`)

- [ ] **Step 4: Implement both services** según las definiciones de arriba. Usa `ActiveRecord::Base.connection.select_all` y castea a `BigDecimal` o a `Integer` al construir el hash.

- [ ] **Step 5: Run tests to verify they pass**

Run: el mismo comando del Step 3. Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/services/finance/period_flows.rb app/services/finance/closing_balances.rb spec/services/finance/period_flows_spec.rb spec/services/finance/closing_balances_spec.rb
git commit -m "feat(finanzas): flujos por periodo y saldos al cierre"
```

---

### Task 4: Estado mensual compuesto y CSV

**Files:**
- Create: `app/services/finance/monthly_statement.rb`, `app/services/finance/statement_csv.rb`
- Test: `spec/services/finance/monthly_statement_spec.rb`, `spec/services/finance/statement_csv_spec.rb`

**Interfaces:**
- Consumes: `Finance::PeriodFlows`, `Finance::ClosingBalances`, `Finance::SaleRecognition.sql`.
- Produces: `Finance::MonthlyStatement.new(year: Integer | nil, today: Date = Time.zone.today).call -> Finance::MonthlyStatement::Result`. Con `year: nil` es la vista histórica: una columna por año.
- `Result` (Struct o `Data.define`) con:
  - `periods: Array<Period>`. `Period` tiene `starts_on: Date`, `ends_on: Date`, `label: String` (`"Ene"`..`"Dic"` o `"2025"`) y `state: :closed | :current | :future`.
  - `rows: Hash{Symbol => Array<BigDecimal|Integer|nil>}`, alineado con `periods`. Llaves en este orden: `:sales, :sales_count, :discounts, :sale_refunds, :cogs, :profit, :margin, :profit_cumulative, :cash_in, :purchases, :refunds, :cashflow, :cashflow_cumulative, :advances, :inventory`. Los periodos `:future` llevan `nil` en todas.
  - `deltas: Hash{profit: Array<BigDecimal|nil>, cashflow: Array<BigDecimal|nil>}`: diferencia contra el periodo anterior, incluido el previo al rango. `nil` en periodos futuros.
  - `totals: Hash{Symbol => BigDecimal|Integer|nil}`. Suma los flujos. `margin` se recalcula del total. Saldos y acumulados toman el valor del último periodo no futuro.
  - `year: Integer|nil`, `first_year: Integer`, `history: Boolean`.
- Produces: `Finance::MonthlyStatement.first_operation_on -> Date|nil`. Es el mínimo entre `concluded_on`, `payments.paid_at` recibidos, `purchase_orders.order_date` no canceladas y la fecha de las altas manuales.
- Produces: `Finance::StatementCsv.new(result).call -> String`. UTF-8 con BOM (`"﻿"`). Primera columna "Concepto", después las etiquetas de los periodos y al final "Total año" (o "Total" en la vista histórica). Números sin formato, con punto decimal; celdas vacías para `nil`.

Cálculos: `profit = sales - discounts - sale_refunds - cogs`. `margin = profit / (sales - discounts)`, o `nil` si el denominador es `<= 0`. `cashflow = cash_in - purchases - refunds`. Los acumulados parten de la suma de todos los periodos anteriores al rango; usa `PeriodFlows` desde `first_operation_on` con `grain: :year` y suma. `first_year = first_operation_on&.year || today.year`. Un periodo es `:current` cuando contiene `today`. Los saldos se piden al `ends_on` de cada periodo no futuro; para el periodo actual, al `today`.

Etiquetas del CSV (las mismas de la vista; definirlas una vez como `Finance::MonthlyStatement::ROW_LABELS`):

```ruby
ROW_LABELS = {
  sales: 'Ventas concluidas', sales_count: 'Órdenes concluidas', discounts: 'Descuentos',
  sale_refunds: 'Reembolsos de ventas', cogs: 'Costo de lo vendido', profit: 'Utilidad del mes',
  margin: 'Margen', profit_cumulative: 'Utilidad acumulada histórica',
  cash_in: 'Cobros (incl. anticipos)', purchases: 'Compras y altas manuales', refunds: 'Reembolsos',
  cashflow: 'Flujo del mes', cashflow_cumulative: 'Flujo acumulado histórico',
  advances: 'Anticipos por entregar', inventory: 'Inventario a costo'
}.freeze
```

En la vista histórica, "Utilidad del mes" y "Flujo del mes" se muestran como "Utilidad del año" y "Flujo del año": la vista decide la etiqueta con `history`.

- [ ] **Step 1: Write the failing tests — `MonthlyStatement`** (`travel_to` 2026-06-15)

```ruby
it 'año: 12 periodos, junio :current, julio..dic :future con nil'
it 'utilidad, margen y flujo del mes'                  # venta 100 costo 60 concluida en marzo, compra 500 en marzo
  # rows[:profit][2] == 40; rows[:margin][2] == 0.4; rows[:cashflow][2] == 100 - 500
it 'acumulados incluyen años anteriores'               # utilidad 25 en 2025 → rows[:profit_cumulative][0] == 25
it 'delta de enero compara contra diciembre del año anterior'
it 'totales: suman flujos y toman saldos del último periodo no futuro'
it 'histórico: una columna por año desde first_year'   # datos en 2024 y 2026 → labels %w[2024 2025 2026]
it 'base vacía: año en curso con ceros y margen nil'
it 'mes con reembolso y sin ventas: margen nil y utilidad negativa'
```

- [ ] **Step 2: Write the failing test — `StatementCsv`**

```ruby
it 'empieza con BOM, encabezados y una fila por concepto'
  # csv.start_with?("﻿"); headers == ['Concepto', 'Ene', ..., 'Dic', 'Total año']
  # fila 'Utilidad del mes' tiene "40.0" en Mar y '' en meses futuros
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/finance/monthly_statement_spec.rb spec/services/finance/statement_csv_spec.rb`
Expected: FAIL (`uninitialized constant`)

- [ ] **Step 4: Implement `MonthlyStatement` and `StatementCsv`** (usa la librería `csv`; agrega `require 'csv'` dentro del archivo, porque es stdlib y no es una gema de dev/test).

- [ ] **Step 5: Run tests to verify they pass**

Run: el mismo comando del Step 3. Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/services/finance/monthly_statement.rb app/services/finance/statement_csv.rb spec/services/finance/monthly_statement_spec.rb spec/services/finance/statement_csv_spec.rb
git commit -m "feat(finanzas): estado mensual compuesto y exportación CSV"
```

---

### Task 5: Controlador, ruta, vista y menú

**Files:**
- Create: `app/controllers/admin/finances_controller.rb`, `app/views/admin/finances/index.html.erb`
- Modify: `config/routes.rb` (junto a `get 'dashboard'`, ~línea 132), `app/views/admin/partials/_sidebar.html.erb:65`
- Test: `spec/requests/admin/finances_spec.rb`

**Interfaces:**
- Consumes: `Finance::MonthlyStatement`, `Finance::StatementCsv`, `Finance::MonthlyStatement::ROW_LABELS`.
- Produces: ruta `get 'finances', to: 'finances#index', as: :finances` dentro del namespace `admin` (helper `admin_finances_path`). Parámetros: `year` (entero) y `view=history`.

Comportamiento:
- `year` se convierte con `Integer(params[:year], exception: false)` y se acota a `[first_year, today.year]`. Si falta o no es válido, usa el año en curso.
- `format.csv`: `send_data Finance::StatementCsv.new(result).call, filename: "finanzas-#{history ? 'historico' : year}-#{Time.zone.today.iso8601}.csv", type: 'text/csv; charset=utf-8'`.
- Vista con `layout 'admin'`:
  - Encabezado "Finanzas".
  - Navegación: "◀ <año-1>" si `year > first_year`, el año actual en negritas, "<año+1> ▶" si `year < today.year`, el enlace "Todo el histórico" (o "Ver por meses" estando en el histórico) y el botón "⬇ CSV" con los mismos parámetros.
  - Tabla dentro de `.table-responsive`, con la primera columna `position: sticky; left: 0` y fondo propio.
  - Tres grupos con encabezado de fila: "Utilidad", "Flujo" y "Saldos al cierre".
  - Las filas `profit` y `cashflow` en negritas, en verde si son `>= 0` y en rojo si son `< 0`, con una flecha ▲/▼ y el delta en texto pequeño.
  - Columna del periodo `:current` con la insignia "en curso". Periodos futuros vacíos.
  - Moneda con el helper `fmt_currency` del panel (`Admin::DashboardHelper#fmt_currency`; si no está disponible en este controlador, `helper Admin::DashboardHelper`). Margen en porcentaje con 1 decimal.
  - Pie de página con este texto exacto: "Finanzas cuenta cada venta en el mes en que el cliente termina de pagar; el Panel de control la cuenta en la fecha de la orden, por eso sus cifras pueden diferir."
- Menú: `<%= admin_sidebar_link 'Finanzas', admin_finances_path, icon: 'scale-balanced' %>` justo debajo de "Cuentas por cobrar".

- [ ] **Step 1: Write the failing request spec** (`sign_in create(:user, :admin)`, `travel_to` 2026-06-15)

```ruby
it 'muestra la tabla del año con las filas de utilidad, flujo y saldos'   # body incluye 'Utilidad del mes', 'Flujo del mes', 'Anticipos por entregar', 'en curso'
it 'muestra la utilidad de la venta en el mes de conclusión'               # venta 100 costo 60 concluida en marzo → celda Mar de 'Utilidad del mes' contiene '40'
it 'vista histórica muestra columnas por año'                              # get admin_finances_path(view: 'history') → encabezados '2026'
it 'acota years inválidos sin error'                                       # %w[abc 1900 3000] + '' → status 200 y título con el año acotado
it 'descarga CSV'                                                          # get admin_finances_path(format: :csv) → content-type text/csv, body empieza con BOM
it 'redirige a no administradores'                                         # sign_in create(:user) → redirect_to root_path
it 'el menú lateral enlaza a Finanzas'                                     # get admin_dashboard_path → link href admin_finances_path
```

- [ ] **Step 2: Run test to verify it fails**

Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/requests/admin/finances_spec.rb`
Expected: FAIL (`undefined method 'admin_finances_path'`)

- [ ] **Step 3: Implement route, controller, view and sidebar link.**

- [ ] **Step 4: Run test to verify it passes**

Run: el mismo comando del Step 2. Expected: 0 failures.

- [ ] **Step 5: Lint, graph, and the finance + dashboard + payments suites**

Run:
```bash
~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app/controllers/admin/finances_controller.rb app/services/finance app/models/payment.rb db/migrate/20261107010000_add_refunded_at_to_payments.rb
~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/services/finance spec/requests/admin/finances_spec.rb spec/requests/admin/dashboard_period_spec.rb spec/services/mercado_pago spec/models
graphify update .
```
Expected: rubocop sin ofensas; rspec 0 failures.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/admin/finances_controller.rb app/views/admin/finances app/views/admin/partials/_sidebar.html.erb spec/requests/admin/finances_spec.rb
git commit -m "feat(finanzas): página Finanzas con tabla mensual, histórico y CSV"
```

- [ ] **Step 7: Full suite before PR** (sin tocar código mientras corre)

Run: `~/.rvm/bin/rvm 3.2.3 do bundle exec rspec`
Expected: 0 failures. Si fallan specs no relacionados, compáralos contra `main` antes de atribuirlos a este cambio.
