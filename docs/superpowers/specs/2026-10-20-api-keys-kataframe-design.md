# Claves de API + API de productos para KataFrame — diseño

Fecha: 2026-10-20
Estado: aprobado en conversación, pendiente de revisión del documento

## Por qué

KataFrame (app de escritorio Windows/Electron del mismo dueño, repo
`alexormx/kataframe-source`) toma fotos de producto, arma collages y genera
catálogos. Necesita conectarse a este inventario en los dos sentidos:

- **leer** los productos (qué fotografiar, con qué datos armar catálogos);
- **crear y editar** productos, y **subir fotos** que se vuelven imágenes del
  producto en la tienda.

Hoy la API (`/api/v1`) se autentica con un único `users.api_token` por admin:
guardado en texto plano, sin pantalla para verlo, renovarlo o revocarlo, y sin
permisos (quien lo tiene puede todo). El dueño quiere un sistema de claves de
verdad: crearlas en el admin, ver cuándo se usaron y revocarlas sin afectar a
nada más.

**Éxito:** el dueño crea en el admin una clave "KataFrame", la pega en el
conector "API propia (REST)" de KataFrame, y desde KataFrame puede listar
productos, crear uno nuevo con fotos, editar nombre/precio/descripción y
agregar fotos a un producto existente, viéndolas luego en la tienda. Revocar la
clave corta el acceso al instante.

## Metas

1. Modelo de claves de API con permisos, gestionado desde el admin.
2. Endpoints de productos (listar, ver, crear, editar con fotos) que encajen
   con el conector REST que KataFrame **ya tiene**, sin cambios en KataFrame.
3. No romper a los clientes actuales de `/api/v1`.

## No metas

- Cambios de código en KataFrame (solo se configura su conector).
- Borrar productos o fotos desde la API.
- Editar existencias, costos, proveedores o estadísticas por la API.
- OAuth, claves por usuario cliente, portal de desarrolladores, webhooks.
- Retirar el `users.api_token` legado (queda para un cambio posterior).

## Anti-metas (fallaría aunque "funcione")

- **Exponer identificadores de proveedor:** `product_sku` y
  `supplier_product_code` nunca aparecen en una respuesta de la API (regla del
  proyecto). Tampoco costos, utilidades, ids de proveedor ni estadísticas de
  compra/venta.
- Guardar las claves en texto plano o poder volver a mostrarlas.
- Que una subida de fotos grandes tumbe el dyno web (Basic, 512 MB).
- Romper el generador de PDF de catálogo o los scripts que hoy usan
  `POST /api/v1/products`, `sales_orders`, etc. con el token legado.

## Restricciones del entorno

- Rails 8, PostgreSQL, Heroku dyno web de 512 MB; Solid Queue en dyno worker
  aparte (los jobs de Active Storage — analyze/variants — corren ahí).
- Respuestas grandes: patrón ya usado en `Api::V1::CatalogController`
  (`find_each`, sin cargar colecciones completas en memoria).
- `custom_attributes` es jsonb en prod y text en local/CI: no usar operadores
  jsonb en consultas.
- Fotos de producto: `has_many_attached :product_images` +
  `primary_product_image_attachment_id` (`Product#ordered_product_images`,
  `#set_primary_product_image!`).

## Diseño

### 1. Modelo `ApiKey`

Tabla `api_keys`:

| columna | tipo | notas |
|---|---|---|
| `name` | string, null: false | "KataFrame – laptop" |
| `token_digest` | string, null: false, índice único | SHA-256 hex del token completo |
| `token_prefix` | string, null: false | primeros caracteres visibles, p. ej. `pk_a1b2c3d4` |
| `scopes` | string array, default `[]`, null: false | ver permisos |
| `created_by_id` | FK users | el admin que la creó |
| `last_used_at` | datetime | |
| `revoked_at` | datetime | no nulo = revocada |
| timestamps | | |

- Formato del token: `pk_` + 32 bytes aleatorios en base58/hex (decisión del
  constructor). Se genera al crear, se devuelve **una sola vez** y solo se
  guarda su digest. Al ser aleatorio de alta entropía, SHA-256 simple basta
  (no hace falta bcrypt); búsqueda por `token_digest` con índice.
- `last_used_at` se actualiza con `update_column` como mucho una vez por
  minuto por clave, para no escribir en cada petición.
- Permisos (`ApiKey::SCOPES`):
  - `products:read` — listar y ver productos.
  - `products:write` — crear y editar productos.
  - `photos:write` — adjuntar fotos (en create/update).

### 2. Autenticación

Extender `ApiTokenAuthenticatable`:

1. Toma `Authorization: Bearer <token>`.
2. Si el token empieza con `pk_`: busca `ApiKey` activa por digest. Si existe,
   `@current_api_key = key`; `@current_user = key.created_by`.
3. Si no: comportamiento legado (`User.find_by(api_token:)` y `admin?`). Una
   petición con token legado tiene **todos** los permisos (compatibilidad).
4. Si nada coincide → `401 {"error":"Unauthorized"}`.

Helper `require_scope!(scope)` → `403 {"error":"Forbidden: missing scope <scope>"}`
si la clave no lo tiene (siempre pasa con token legado).

Los controladores existentes (`sales_orders`, `payments`, items,
`users`, `catalog`) no cambian de comportamiento con el token legado. *Mi
decisión:* con una clave nueva, `catalog` exige `products:read`; los demás
endpoints existentes (órdenes, usuarios, pagos) **rechazan** claves nuevas con
403 hasta que se definan permisos para ellos — así una clave de KataFrame no
puede tocar órdenes.

### 3. Pantalla de admin "Claves de API"

`Admin::ApiKeysController` (index, new, create, revoke), en el menú del admin,
estilo de las demás pantallas del admin:

- **Lista:** nombre, prefijo, permisos, creada por, creada el, último uso,
  estado (activa/revocada). Revocadas visibles pero atenuadas.
- **Nueva:** nombre + casillas de permisos (las tres marcadas por defecto).
- **Tras crear:** página que muestra el token completo una vez, con botón de
  copiar y aviso "no se volverá a mostrar". Recargar no lo vuelve a mostrar
  (no se guarda en la sesión más allá de esa respuesta; usar `flash.now` o
  render directo, no redirect con el token en la URL).
- **Revocar:** botón con confirmación; pone `revoked_at`. Sin "des-revocar".
- Solo admins.

### 4. Endpoints de productos para KataFrame

Todo bajo `/api/v1/products`, JSON. Configuración que se pondrá en KataFrame:

| ajuste KataFrame | valor |
|---|---|
| authHeader / authScheme | `Authorization` / `Bearer` |
| listPath | `/api/v1/products` |
| itemsPath | `items` |
| createPath | `/api/v1/products` |
| updatePath | `/api/v1/products/{id}` |
| updateMethod | `PATCH` |
| bodyWrapper | `product` |
| idKey | `id` |
| photoUpload | sí |
| photoField | `product[product_images][]` |
| photoUrlsPath | `image_urls` |

#### Representación de un producto (lectura)

```json
{
  "id": 123,
  "code": "AB12",
  "product_name": "...",
  "brand": "...",
  "category": "...",
  "series": "...",
  "scale": "1:64",
  "selling_price": "199.0",
  "description": "...",
  "status": "active",
  "barcode": "...",
  "launch_date": "2026-09-01",
  "stock_available": 3,
  "length_cm": "8.0", "width_cm": "4.0", "height_cm": "4.0", "weight_gr": "50.0",
  "custom_attributes": { },
  "image_urls": ["https://.../primary.jpg", "https://.../2.jpg"],
  "updated_at": "..."
}
```

- `code` = `whatsapp_code` (identificador público).
- `image_urls` en el orden de `ordered_product_images` (principal primero);
  URLs absolutas permanentes de la foto **original** (blob, no variante).
  *Mi decisión:* NO usar el criterio de `CatalogPdf::ProductSource#image_url`
  (variante 600×600): un listado completo dispararía cientos de variantes
  ImageMagick en el dyno web, y KataFrame reutiliza estas fotos para otras
  tiendas, así que deben ir en calidad completa.
- `stock_available`: piezas disponibles para vender (misma definición que usa
  la tienda/catálogo; el constructor elige el método existente).
- Lista blanca de campos en un serializador; **nunca** `product_sku`,
  `supplier_product_code`, costos, utilidades, proveedores, totales.

#### `GET /api/v1/products` — `products:read`

- *Mi decisión:* devuelve **todos** los productos, incluidos borradores,
  inactivos y agotados (se fotografía antes de publicar); `status` va en cada
  ítem para que KataFrame filtre.
- Paginado por cursor o página, 100 por página:
  `{"items":[...], "next":"https://.../api/v1/products?page=2"}`; `next` es
  URL absoluta o se omite en la última página (KataFrame sigue `next`).
- Precargar adjuntos (`with_attached_product_images`) para evitar N+1; no
  cargar el catálogo entero en memoria.
- Filtro opcional `updated_since` (ISO 8601) — barato y útil, decisión del
  constructor si entra.

#### `GET /api/v1/products/:id` — `products:read`

Un producto con la misma representación.

#### `POST /api/v1/products` — `products:write` (+ `photos:write` si trae fotos)

Acepta JSON (`{"product":{...}}`) o multipart (`product[campo]` +
`product[product_images][]`). Campos escribibles:
`product_name, brand, category, series, scale, selling_price, description,
barcode, launch_date, status, whatsapp_code, length_cm, width_cm, height_cm,
weight_gr, custom_attributes`.

- **Compatibilidad:** hoy este endpoint lo usan scripts externos con el token
  legado y parámetros que incluyen `product_sku`, `supplier_product_code`,
  `maximum_discount`, `minimum_price`. Con token legado se mantiene el
  conjunto de parámetros actual. Con clave nueva se usa la lista de arriba.
- `product_sku` es obligatorio y único en el modelo, pero KataFrame no lo
  conoce. **Decisión del dueño:** con clave nueva se genera automáticamente,
  con el mismo patrón que `Collectibles::QuickAddService#generate_sku`
  (prefijo propio, p. ej. `KF` + 3 letras de categoría + timestamp; garantizar
  unicidad si dos llegan en el mismo segundo). Con clave nueva no se acepta
  `product_sku` de entrada. El admin lo puede corregir después en la edición
  normal del producto (verificar que el formulario del admin lo permite) para
  reconciliar con la sincronización de proveedores, que empareja por
  `barcode` → `product_sku` → `supplier_product_code`.
- Respuesta `201` con la representación completa (incluye `id` e
  `image_urls`). Errores de validación: `422 {"errors":[...]}` (KataFrame
  muestra `errors` tal cual).
- Mantener `Products::UpdateStatsService` como hoy.

#### `PATCH /api/v1/products/:id` — `products:write` y/o `photos:write`

- Solo cambia los campos que vienen (mismos campos escribibles).
- *Mi decisión:* `custom_attributes` se **fusiona** con lo existente (KataFrame
  manda solo las llaves que mapea; reemplazar borraría las demás, incluida la
  que alimenta `series`). Una llave con `""` o `null` se elimina. Hacer la
  fusión en Ruby sobre el hash ya parseado, sin operadores jsonb (deriva
  jsonb/text entre prod y local).
- Fotos en `product[product_images][]` se **agregan al final**; nunca se
  borran ni reordenan. La principal no cambia; si el producto no tenía fotos,
  la primera subida queda como principal (comportamiento actual de
  `clear_primary_product_image_if_missing!` / orden por `created_at`; el
  constructor verifica).
- Una petición solo con fotos requiere `photos:write`; una con campos requiere
  `products:write`.
- Respuesta `200` con la representación completa; KataFrame compara
  `image_urls` antes/después para saber qué URL quedó para cada foto subida,
  así que las nuevas deben aparecer **al final y en el orden enviado**.

#### Publicar y despublicar (`status`) — create y PATCH

Los productos de la API son **los mismos** de la tienda (misma tabla
`products`); KataFrame puede publicar tanto productos que creó como productos
que ya existían.

- **Decisión del dueño:** misma regla que el admin. Si llega
  `status: "active"`, solo se acepta si `product.eligible_for_publication?`
  (stock publicable, preventa o backorder); si no, `422` con
  `"No se puede publicar: el producto no tiene existencias publicables, ni preventa ni backorder"`.
  Al publicar se limpia `auto_paused` como en
  `Admin::ProductsController#publish_if_eligible` (reutilizar/extraer esa
  lógica, no duplicarla). El sello de `first_published_at` /
  `republished_at` queda tal cual lo hace el modelo hoy.
- Pasar a `inactive` o `draft` siempre se permite.
- En create, un producto recién creado casi nunca tiene stock. *Mi
  decisión:* si pide `active` y no es elegible, se rechaza todo el create con
  `422` (sin crear nada), para que KataFrame no quede con un producto creado
  en la tienda cuyo id nunca recibió.

#### Fotos: límites

- Solo `image/jpeg`, `image/png`, `image/webp`; **10 fotos** por petición
  (decisión del dueño) y *mi decisión* **15 MB** por foto → `422` con mensaje
  claro si se pasa. Riesgo conocido: 10 fotos grandes en una sola petición
  pueden acercarse al timeout de 30 s del router de Heroku; si pasa en la
  práctica, el siguiente paso es subida directa a S3, fuera de este alcance.
- El controlador solo adjunta; no procesa con ImageMagick en la petición.
  Análisis y variantes ocurren en jobs/a demanda como hoy.
- **Mismo guardado que el admin** (confirmado por el dueño): la foto se
  guarda original, sin redimensionar; la tienda genera sus variantes
  (galería 320/480/600, miniaturas) a demanda como con cualquier otra foto.
- EXIF/GPS: no se limpia del lado del inventario (limpiarlo en el worker
  cambiaría la URL después de la respuesta y KataFrame perdería el
  emparejamiento; en la petición costaría memoria del dyno web). Queda como
  mejora futura **en KataFrame**: quitar metadatos antes de enviar.

### 5. Errores

Formato uniforme: `{"error": "..."}` para 401/403/404, `{"errors": [...]}`
para 422. 404 si el producto no existe.

## Pruebas (constructor)

- Modelo `ApiKey`: generación, digest, revocación, scopes válidos.
- Request specs: 401 sin token / token inválido / clave revocada; 403 sin
  scope; token legado sigue funcionando en create y en `catalog`; clave nueva
  rechazada en órdenes; listado paginado con `next`; la respuesta **no**
  contiene `product_sku` ni `supplier_product_code` (aserción explícita);
  PATCH agrega fotos al final y no cambia la principal; límites de fotos.
- System/feature spec de la pantalla de admin: crear muestra el token una
  vez, revocar.

## Lo que queda al constructor

Formato exacto del token, paginación por página vs cursor, nombre/ubicación
del serializador, diseño visual de la pantalla de admin dentro del estilo
existente, si entra `updated_since`, rate limiting (opcional, `rate_limit` de
Rails 8 si es trivial).

## Preguntas abiertas

Ninguna.
