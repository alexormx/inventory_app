# Claves de API + API de productos para KataFrame — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claves de API con permisos gestionadas desde el admin, y endpoints `/api/v1/products` (listar, ver, crear, editar, agregar fotos, publicar) que encajen con el conector "API propia (REST)" de KataFrame sin cambiarlo.

**Architecture:** Modelo `ApiKey` (digest SHA-256, scopes en array) + `ApiTokenAuthenticatable` extendido para aceptar claves `pk_` además del `users.api_token` legado. Lectura vía un serializador de lista blanca; escritura vía un servicio `Api::ProductWriter` que concentra SKU, fusión de `custom_attributes`, regla de publicación y fotos. Pantalla `Admin::ApiKeysController`.

**Tech Stack:** Rails 8, PostgreSQL, Active Storage (S3 en prod, proxy), Kaminari, RSpec + FactoryBot + Warden helpers.

**Spec:** `docs/superpowers/specs/2026-10-20-api-keys-kataframe-design.md`

## Global Constraints

- Nunca en una respuesta de la API: `product_sku`, `supplier_product_code`, costos (`*_cost`, `*_purchase_*`), utilidades/proyecciones, `preferred_supplier_id`, `last_supplier_id`, estadísticas de venta. Lista blanca, no lista negra.
- Tokens: se muestran una sola vez; en BD solo `token_digest` (SHA-256 hex) + `token_prefix`.
- Scopes exactos: `products:read`, `products:write`, `photos:write`.
- Token legado (`users.api_token` de admin) = todos los permisos y comportamiento actual intacto en todos los endpoints existentes.
- Clave nueva en `sales_orders`, `payments`, `purchase_orders`, `*_order_items`, `users` → `403`.
- Fotos: `image/jpeg|png|webp`, máx **10 por petición**, máx **15 MB** c/u → `422`. Se adjuntan originales, sin ImageMagick en la petición. Se agregan al final; la principal no cambia.
- `image_urls`: URL absoluta del **original** (`rails_storage_proxy_url(attachment)`, no variante), en el orden de `ordered_product_images`.
- Publicar (`status: "active"`) solo si `product.eligible_for_publication?`; si no, `422` con `"No se puede publicar: el producto no tiene existencias publicables, ni preventa ni backorder"`. En create, ese 422 no crea nada.
- SKU de productos creados con clave nueva: generado, prefijo `KF`; clave nueva no puede mandar `product_sku`.
- `custom_attributes` en PATCH se fusiona; valor `""`/`null` borra la llave. Fusión en Ruby, sin operadores jsonb (deriva jsonb/text prod vs local).
- Errores: `{"error": "..."}` para 401/403/404; `{"errors": [...]}` para 422.
- Invocar Ruby con `~/.rvm/bin/rvm 3.2.3 do …`. Migraciones solo `db:migrate` (dev y `RAILS_ENV=test`); nunca comandos destructivos de BD. Test DB con `db:test:prepare`, nunca `db:prepare`.
- Copia de UI en español, estilo de las pantallas admin existentes.

## Review Focus

1. Encabezado `Authorization: Token <legado>` (lo usan los specs y scripts actuales) y `Bearer pk_…` — ambos deben autenticar; `bearer` en minúsculas también. → test en Task 2.
2. PATCH multipart **solo con fotos** (sin otros campos de `product`) y PATCH JSON sin `product` → no debe dar 400 por `params.expect`; fotos-solo exige solo `photos:write`. → test en Task 5.
3. Multipart convierte todo a texto: `product[custom_attributes][color]=""`, `product[selling_price]="199"` → `""` borra la llave; precio se castea. → test en Task 5.
4. Clave revocada después de crearla (o creador ya no admin) → 401 inmediato. → test en Task 2.
5. Listado con `?page=` fuera de rango → `{"items":[]}` sin `next`, nunca bucle infinito en KataFrame. → test en Task 4.

---

### Task 1: Modelo `ApiKey`

**Files:**
- Create: `db/migrate/<ts>_create_api_keys.rb`, `app/models/api_key.rb`, `spec/factories/api_keys.rb`, `spec/models/api_key_spec.rb`

**Interfaces:**
- Produces:
  - `ApiKey::SCOPES = %w[products:read products:write photos:write].freeze`
  - `ApiKey.generate!(name:, scopes:, created_by:) -> [ApiKey, String]` (String = token en claro, `pk_` + `SecureRandom.base58(40)`)
  - `ApiKey.authenticate(token) -> ApiKey | nil` (activa, por digest; nil si revocada o token no `pk_`)
  - `ApiKey.digest(token) -> String`
  - `#allows?(scope) -> Boolean`, `#revoke!`, `#revoked?`, `#touch_last_used!` (como mucho 1 escritura/min, `update_column`)
  - `scope :active` (`revoked_at: nil`)
  - Factory `:api_key` (asocia `created_by` admin, scopes = todos) — construir con `ApiKey.generate!` en specs cuando se necesite el token.

- [ ] **Step 1: Migración** — tabla `api_keys`: `name` string null:false; `token_digest` string null:false índice único; `token_prefix` string null:false; `scopes` string array default `[]` null:false; `created_by_id` references `users` null:false FK; `last_used_at`, `revoked_at` datetime; timestamps.
- [ ] **Step 2: Migrar** — `~/.rvm/bin/rvm 3.2.3 do bin/rails db:migrate && RAILS_ENV=test ~/.rvm/bin/rvm 3.2.3 do bin/rails db:migrate`. Esperado: `db/schema.rb` con `api_keys`. (Si Postgres no corre, pedir al usuario `! sudo service postgresql start`.)
- [ ] **Step 3: Tests que fallan** en `spec/models/api_key_spec.rb`:
  - `generate!` devuelve token que empieza con `pk_`, `token_digest == ApiKey.digest(token)`, `token_prefix == token.first(11)`, y el token en claro no aparece en ningún atributo guardado.
  - `authenticate(token)` devuelve la clave; `nil` tras `revoke!`; `nil` para `"pk_inexistente"`, `""`, `nil` y para un token legado hex.
  - `scopes` inválido (`["orders:write"]`) → inválido; scopes vacío → inválido; `name` en blanco → inválido.
  - `touch_last_used!` dos veces en el mismo minuto escribe una vez (`travel_to`); a los 61 s vuelve a escribir.
  - `allows?("products:read")` según scopes.
- [ ] **Step 4: Correr** `~/.rvm/bin/rvm 3.2.3 do bundle exec rspec spec/models/api_key_spec.rb` → FAIL (constante no definida).
- [ ] **Step 5: Implementar** `app/models/api_key.rb` (`belongs_to :created_by, class_name: 'User'`; validación de scopes ⊆ SCOPES y no vacío; `Digest::SHA256.hexdigest`).
- [ ] **Step 6: Correr** el spec → PASS.
- [ ] **Step 7: Commit** `feat: modelo ApiKey con digest y permisos`

### Task 2: Autenticación con claves + permisos

**Files:**
- Modify: `app/controllers/concerns/api_token_authenticatable.rb`
- Modify: `app/controllers/api/v1/{sales_orders,payments,purchase_orders,purchase_order_items,sale_order_items,users}_controller.rb` (agregar `before_action :reject_api_keys!`)
- Modify: `app/controllers/api/v1/catalog_controller.rb` (`before_action -> { require_scope!('products:read') }`)
- Test: `spec/requests/api/v1/api_key_auth_spec.rb`

**Interfaces:**
- Consumes: `ApiKey.authenticate`, `#allows?`, `#touch_last_used!`.
- Produces (privados en el concern, disponibles a todos los controladores API):
  - `authenticate_with_token!` — setea `@current_user` y, si fue clave, `@current_api_key`.
  - `current_api_key -> ApiKey | nil` (nil = token legado)
  - `legacy_token? -> Boolean`
  - `require_scope!(scope)` → 403 `{"error":"Forbidden: missing scope <scope>"}`; siempre pasa con legado.
  - `reject_api_keys!` → 403 `{"error":"Forbidden: API keys cannot access this endpoint"}` si hay `current_api_key`.

Regla: token = última palabra del header `Authorization` (acepta `Bearer`, `bearer`, `Token`). Si empieza con `pk_`: `ApiKey.authenticate`; válida solo si `created_by.admin?`. Si no `pk_`: flujo legado actual. Falla → 401 `{"error":"Unauthorized"}`.

- [ ] **Step 1: Tests que fallan** en `api_key_auth_spec.rb` (usa `GET /api/v1/catalog` como endpoint de lectura y `POST /api/v1/sales_orders` como endpoint de órdenes):
  - sin header → 401; `Bearer pk_basura` → 401; clave revocada → 401; clave cuyo creador pasó a `customer` → 401.
  - clave con `products:read` → catalog 200, y `last_used_at` queda puesto.
  - clave sin `products:read` (solo `photos:write`) → catalog 403 con `"Forbidden: missing scope products:read"`.
  - `bearer pk_…` en minúsculas → 200.
  - token legado con `Token <api_token>` y con `Bearer <api_token>` → catalog 200.
  - clave con todos los scopes → `POST /api/v1/sales_orders` 403; token legado sigue pasando la autenticación (no 401/403).
- [ ] **Step 2: Correr** → FAIL.
- [ ] **Step 3: Implementar** concern y los `before_action` listados.
- [ ] **Step 4: Correr** el spec nuevo + `spec/requests/api` completo → PASS (los specs existentes de órdenes no cambian).
- [ ] **Step 5: Commit** `feat: autenticación de API con claves y permisos`

### Task 3: Pantalla admin "Claves de API"

**Files:**
- Create: `app/controllers/admin/api_keys_controller.rb`, `app/views/admin/api_keys/{index,new,created}.html.erb`
- Modify: `config/routes.rb` (dentro de `namespace :admin`: `resources :api_keys, only: %i[index new create] do member { patch :revoke } end`), `app/views/admin/partials/_sidebar.html.erb` (link "Claves de API", icon `key`, en sección Sistema)
- Test: `spec/requests/admin/api_keys_spec.rb`

**Interfaces:**
- Consumes: `ApiKey.generate!`, `#revoke!`, `ApiKey::SCOPES`.
- Controller: `before_action :authenticate_user!, :authorize_admin!` (patrón de `Admin::SettingsController`). `create` hace **render** de `created` (status 201 o 200) con el token en `@token` — sin redirect ni flash con el token. `revoke` → redirect a index con notice.

Etiquetas de permisos en la vista: `products:read` "Leer productos", `products:write` "Crear y editar productos", `photos:write` "Subir fotos". Las tres marcadas por defecto en `new`.

- [ ] **Step 1: Tests que fallan** (`login_as(admin, scope: :user)` como en `spec/requests/admin_products_spec.rb`):
  - no admin → redirigido/sin acceso; admin ve index con nombre, `token_prefix`, permisos y "Nunca" si `last_used_at` nil.
  - `POST create` con nombre y scopes → crea 1 `ApiKey`; el body contiene el token completo (`/pk_[1-9A-HJ-NP-Za-km-z]{40}/`) y el texto "no se volverá a mostrar"; `GET index` después NO contiene ese token.
  - `POST create` sin scopes → no crea, re-render con error.
  - `PATCH revoke` → `revoked_at` presente; index la marca "Revocada" y sin botón de revocar.
- [ ] **Step 2: Correr** → FAIL.
- [ ] **Step 3: Implementar** controlador, rutas, vistas (estilo Bootstrap de `admin/system_variables`/`payment_methods`), link en sidebar (agregar `admin_api_keys_path` al `also:` de Configuración o link propio).
- [ ] **Step 4: Correr** → PASS.
- [ ] **Step 5: Commit** `feat: pantalla de admin para claves de API`

### Task 4: Lectura de productos (`GET index` / `GET show`)

**Files:**
- Create: `app/serializers/api/v1/product_serializer.rb` (o `app/services/api/v1/product_serializer.rb` si no existe `app/serializers` — seguir lo que haya)
- Modify: `app/controllers/api/v1/products_controller.rb`, `config/routes.rb` (`resources :products, only: %i[index show create update]`; mantener `get 'products/exists'` **antes** del `resources` para que no lo capture `show`)
- Test: `spec/requests/api/v1/products_read_spec.rb`

**Interfaces:**
- Produces:
  - `Api::V1::ProductSerializer.new(product, url_builder:, stock_available:).as_json -> Hash` con exactamente las llaves del spec: `id, code, product_name, brand, category, series, scale, selling_price, description, status, barcode, launch_date, stock_available, length_cm, width_cm, height_cm, weight_gr, custom_attributes, image_urls, updated_at`. `code` = `whatsapp_code`; `custom_attributes` como Hash (parsear si viene String).
  - `Api::V1::ProductsController#render_product(product, status:)` — usado por Task 5.
  - `stock_available` por lote: `Inventory.customer_available_now.where(product_id: ids).group(:product_id).count` (una consulta por página); en `show`, el mismo cálculo para un id.

Index: `with_attached_product_images`, orden `id ASC`, `page(params[:page]).per(100)`; respuesta `{"items":[...], "next": <url absoluta>}`, `next` omitido en la última página. Filtro opcional `updated_since` (ISO 8601; inválido → 422). Todo con `require_scope!('products:read')`. `show` 404 → `{"error":"Not found"}`.

- [ ] **Step 1: Tests que fallan:**
  - lista incluye productos `draft`, `inactive` y `active`; cada ítem tiene `status`.
  - **ninguna** respuesta (index ni show) contiene las llaves ni los valores de `product_sku` y `supplier_product_code` (asertar sobre `response.body` con valores únicos sembrados, p. ej. `"SECRET-SKU-123"`), ni `average_purchase_cost`.
  - las llaves de cada ítem == lista exacta de arriba.
  - `image_urls` en orden con la principal primero (producto con 2 fotos y `set_primary_product_image!` a la segunda) y URLs absolutas sin `variants` en la ruta.
  - `stock_available` == piezas `available` con ubicación y sin orden.
  - con 101 productos: página 1 tiene 100 ítems y `next` absoluto; seguir `next` da 1 ítem y sin `next`.
  - `?page=999` → `{"items":[]}` sin `next`.
  - `updated_since` filtra; `updated_since=basura` → 422.
  - `show` existente 200, inexistente 404; `GET /api/v1/products/exists?whatsapp_code=…` sigue respondiendo `{"exists":…}`.
- [ ] **Step 2: Correr** → FAIL.
- [ ] **Step 3: Implementar** serializador, `index`, `show`, rutas.
- [ ] **Step 4: Correr** → PASS.
- [ ] **Step 5: Commit** `feat: API de lectura de productos para KataFrame`

### Task 5: Escritura — crear, editar, fotos, publicar

**Files:**
- Create: `app/services/api/product_writer.rb`, `spec/services/api/product_writer_spec.rb`
- Modify: `app/controllers/api/v1/products_controller.rb` (`create` con dos ramas, `update`), `app/controllers/admin/products_controller.rb` (`publish_if_eligible` delega en `Product#publish_if_eligible!`), `app/models/product.rb` (`publish_if_eligible! -> Boolean`, `generate_api_sku -> String`)
- Test: `spec/requests/api/v1/products_write_spec.rb`

**Interfaces:**
- Consumes: Task 2 (`current_api_key`, `legacy_token?`, `require_scope!`), Task 4 (`render_product`).
- Produces:
  - `Api::ProductWriter::WRITABLE = %i[product_name brand category series scale selling_price description barcode launch_date status whatsapp_code length_cm width_cm height_cm weight_gr].freeze` (+ `custom_attributes` aparte)
  - `Api::ProductWriter.new(product:, attrs:, photos:).call -> Result(success?, product, errors)`; `product` nuevo o existente. Dentro de una transacción: asigna `attrs`; fusiona `custom_attributes`; si producto nuevo sin `product_sku`, `product.generate_api_sku`; valida fotos; maneja `status: 'active'` con `eligible_for_publication?` (agregando el mensaje exacto a `errors` y haciendo rollback); guarda; adjunta fotos en orden; `Products::UpdateStatsService` solo en create (como hoy).
  - `Api::ProductWriter::MAX_PHOTOS = 10`, `MAX_PHOTO_BYTES = 15.megabytes`, `PHOTO_TYPES = %w[image/jpeg image/png image/webp]`. Mensajes: `"Máximo 10 fotos por petición"`, `"La foto <nombre> pesa más de 15 MB"`, `"La foto <nombre> no es JPG, PNG ni WebP"`.
  - `Product#generate_api_sku` → `"KF" + category.first(3).upcase (o "XXX") + Time.current.strftime('%y%m%d%H%M%S') + SecureRandom.alphanumeric(3).upcase` (sufijo evita choques en el mismo segundo).
  - `Product#publish_if_eligible! -> Boolean` = lógica actual del admin (`update(status: 'active', auto_paused: false)` si elegible).

Controller:
- Leer `product` con `params.fetch(:product, {})` (no `params.expect`) para que fotos-solo y cuerpo vacío no den 400.
- `create`: si `legacy_token?` → comportamiento actual intacto (mismos params incluidos `product_sku`, `supplier_product_code`, mismo JSON de respuesta). Si clave → `require_scope!('products:write')`, más `photos:write` si hay fotos; `ProductWriter`; 201 con `render_product`.
- `update`: con clave o legado; requiere `products:write` si hay algún campo además de fotos, `photos:write` si hay fotos; vacío → 200 sin cambios. `product_sku`/`supplier_product_code` en params con clave → ignorados.

- [ ] **Step 1: Tests de servicio que fallan** (`product_writer_spec.rb`):
  - crea producto con campos mínimos de KataFrame (`product_name, brand, category, selling_price`) → SKU generado empieza con `KF`; dos creaciones en el mismo segundo (`freeze_time`) → SKUs distintos.
  - `custom_attributes`: existente `{"series"=>"A","color"=>"rojo"}` + `{"color"=>"azul"}` → `{"series"=>"A","color"=>"azul"}`; `{"color"=>""}` → `{"series"=>"A"}`.
  - fotos: producto con 2 fotos + 2 nuevas → 4, nuevas al final y en el orden enviado; `primary_product_image` sin cambio. Producto sin fotos + 1 → esa es la principal.
  - 11 fotos → error `"Máximo 10 fotos por petición"` y nada adjuntado; foto `text/plain` → error; foto de 15 MB + 1 byte → error (stub `byte_size`/`size`).
  - `status: 'active'` sin stock ni preventa/backorder → error con el mensaje exacto y **ningún cambio persistido** (ni otros campos); con `preorder_available: true` → activo y `auto_paused` false.
  - create con `status: 'active'` no elegible → no se crea producto (`Product.count` igual).
- [ ] **Step 2: Correr** → FAIL.
- [ ] **Step 3: Implementar** `Api::ProductWriter`, `Product#generate_api_sku`, `Product#publish_if_eligible!`, y cambiar `Admin::ProductsController#publish_if_eligible` para delegar.
- [ ] **Step 4: Correr** servicio + `spec/requests/admin_products_spec.rb` → PASS.
- [ ] **Step 5: Tests de request que fallan** (`products_write_spec.rb`, usando `fixture_file_upload` con las imágenes de `spec/fixtures`):
  - `POST` JSON con clave → 201, cuerpo = representación de Task 4, sin `product_sku`.
  - `POST` multipart como lo manda KataFrame (`product[product_name]`, …, `product[product_images][]` ×2) → 201 con 2 `image_urls`.
  - `POST` con clave mandando `product[product_sku]=X` → SKU guardado empieza con `KF`, no `X`.
  - `POST` con token legado y payload actual (incl. `product_sku`) → 201 con `{"message":"Product created","id":…,"image_urls":[…]}` igual que hoy.
  - `PATCH` multipart **solo fotos** con clave que tiene solo `photos:write` → 200; `image_urls` nuevas al final.
  - `PATCH` con `product[selling_price]` y clave solo `photos:write` → 403 `missing scope products:write`.
  - `PATCH` multipart `product[custom_attributes][color]=""` → llave borrada.
  - `PATCH status=active` no elegible → 422 `{"errors":["No se puede publicar: …"]}`; con stock publicable → 200 `status:"active"`.
  - `PATCH` producto inexistente → 404; validación (`selling_price: 0`) → 422 `{"errors":[…]}`.
- [ ] **Step 6: Correr** → FAIL; **implementar** acciones del controlador; **correr** → PASS.
- [ ] **Step 7: Commit** `feat: API de escritura de productos con fotos y publicación`

### Task 6: Verificación final y guía de conexión

**Files:**
- Create: `docs/api_kataframe.md` (tabla de configuración del conector de la sección 4 del spec + cómo crear la clave + scopes)

- [ ] **Step 1:** Escribir `docs/api_kataframe.md`.
- [ ] **Step 2:** `~/.rvm/bin/rvm 3.2.3 do bundle exec rubocop app config` → sin ofensas nuevas.
- [ ] **Step 3:** `~/.rvm/bin/rvm 3.2.3 do bundle exec brakeman -q --no-pager` → sin advertencias nuevas.
- [ ] **Step 4:** Suite completa `~/.rvm/bin/rvm 3.2.3 do bundle exec rspec` (sin tocar código mientras corre) → verde, salvo fallas preexistentes confirmadas en `main`.
- [ ] **Step 5:** `graphify update .`
- [ ] **Step 6: Commit** `docs: guía para conectar KataFrame a la API`
