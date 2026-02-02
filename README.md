# 🏪 Pasatiempos - Sistema de Gestión de Inventario

Sistema completo de gestión de inventario para tienda de hobbies, desarrollado con Rails 8.0.1 y Ruby 3.2.3.

## 🌐 Producción

- **URL:** https://pasatiempos.com.mx
- **Heroku:** evening-anchorage-70843

---

## 📋 Tabla de Contenidos

- [Características Principales](#-características-principales)
- [Arquitectura](#-arquitectura)
- [Gestión de Inventario](#-gestión-de-inventario)
- [Ubicaciones de Almacén](#-ubicaciones-de-almacén)
- [Órdenes de Compra y Venta](#-órdenes-de-compra-y-venta)
- [API REST](#-api-rest)
- [Desarrollo Local](#-desarrollo-local)
- [Testing](#-testing)

---

## ✨ Características Principales

### Panel de Administración
- Dashboard con métricas y visualizaciones (ECharts)
- Gestión completa de productos con imágenes
- Control de inventario individual por pieza
- Órdenes de compra y venta
- Ajustes de inventario con trazabilidad
- Sistema de ubicaciones jerárquico

### Catálogo Público
- Búsqueda y filtros avanzados
- Categorías y marcas
- Carrito de compras
- Checkout con múltiples métodos de pago

### Autenticación y Roles
- Devise con roles: `admin`, `customer`
- Acceso restringido al panel de administración

---

## 🏗 Arquitectura

### Stack Tecnológico
| Componente | Tecnología |
|------------|------------|
| Framework | Rails 8.0.1 |
| Ruby | 3.2.3 |
| Base de datos | PostgreSQL (prod), SQLite (dev/test) |
| Frontend | Bootstrap 5, Stimulus, Turbo |
| JavaScript | esbuild + importmap |
| Gráficas | ECharts |
| Hosting | Heroku |

### Patrón de Servicios
La lógica de negocio vive en `app/services/`:
- `ApplyInventoryAdjustmentService` - Ajustes de inventario con FIFO
- `Products::UpdateStatsService` - Recálculo de métricas de producto
- `ReverseInventoryAdjustmentService` - Reversión de ajustes

### Seguimiento Individual de Inventario
Cada pieza física se rastrea individualmente en la tabla `inventories`:
- Estados: `available`, `reserved`, `sold`, `in_transit`, `damaged`, `lost`, `scrap`, `marketing`
- FIFO para consumo de piezas
- Sincronización automática con órdenes de compra/venta

---

## 📦 Gestión de Inventario

### Vista Principal (`/admin/inventory`)
- Listado de productos con conteos por estado
- Filtros por estado y búsqueda por nombre/SKU
- Exportación a CSV
- Expansión para ver piezas individuales de cada producto

### Funcionalidades de Piezas
Cada pieza de inventario muestra:
- ID único
- Estado (con edición inline)
- **Ubicación** (con edición inline)
- Origen (Orden de Compra)
- Destino (Orden de Venta)
- Costo y precio de venta

---

## 🗺 Ubicaciones de Almacén

### Estructura Jerárquica (`/admin/inventory_locations`)
Sistema de ubicaciones multinivel para organizar el almacén:
- **Tipos configurables:** Bodega → Sección → Estante → Nivel → Posición
- **Vista de árbol** con contadores de inventario por nivel
- **Contadores duales:** piezas directas y total incluyendo sub-ubicaciones

### Gestión de Ubicaciones
| Función | URL | Descripción |
|---------|-----|-------------|
| Ver estructura | `/admin/inventory_locations` | Árbol con contadores |
| Detalle | `/admin/inventory_locations/:id` | Info + tabla de inventario |
| Sin ubicar | `/admin/inventory/unlocated` | Asignación masiva |
| Transferir | `/admin/inventory/transfer` | Mover entre ubicaciones |

### Asignación Masiva (`/admin/inventory/unlocated`)
- Filtrar por nombre/SKU
- Ordenar por nombre o cantidad
- Paginación (20 productos por página)
- Carga diferida de detalles (AJAX)
- Selección múltiple con cantidades personalizadas
- Búsqueda de ubicación destino

### Transferencia entre Ubicaciones (`/admin/inventory/transfer`)
- Panel dual: origen y destino
- Carga AJAX del inventario por ubicación
- Selección múltiple de piezas
- Validación de ubicaciones diferentes
- Transferencia instantánea

### Edición Individual de Ubicación
En el detalle de inventario de cada producto:
- Botón de lápiz (✏️) para editar ubicación
- Búsqueda de ubicación con autocompletado
- Opción de quitar ubicación
- Solo disponible para piezas `available` o `reserved`

---

## 🧾 Ajustes de Inventario

### Ledger de Ajustes (`/admin/inventory_adjustments`)
Registra aumentos y disminuciones manuales con trazabilidad completa.

#### Estados
- `draft` - Editable, sin efecto en inventario
- `applied` - Inmutable, cambios aplicados

#### Referencia
Formato: `ADJ-YYYYMM-NN` (ej: `ADJ-202509-01`)

#### Tipos de Línea
| Dirección | Efecto |
|-----------|--------|
| `increase` | Crea nuevas piezas de inventario |
| `decrease` | Marca piezas existentes según razón |

#### Condición de Piezas (Para Coleccionables)
Al crear líneas de tipo `increase`, puedes especificar la condición:

| Condición | Descripción |
|-----------|-------------|
| `brand_new` | Nuevo sellado (default) |
| `misb` | Mint In Sealed Box |
| `moc` | Mint On Card |
| `mib` | Mint In Box |
| `mint` | Mint (sin empaque) |
| `loose` | Suelto |
| `good` | Buen estado |
| `fair` | Aceptable |

También puedes asignar un **precio de venta individual** para piezas con valor especial.

#### Razones de Decrease
| Reason | Estado destino |
|--------|----------------|
| scrap | scrap |
| marketing | marketing |
| lost | lost |
| damaged | damaged |

#### Características
- Múltiples líneas por producto permitidas
- Validación de stock agrupando decreases
- FIFO para selección de piezas a decrementar
- Reversible (`reverse!`)
- Trazabilidad vía `adjustment_reference`

---

## 💎 Agregar Coleccionables (Productos Usados)

### Quick Add Collectible (`/admin/collectibles/quick_add`)
Interfaz rápida para agregar productos coleccionables o usados en un solo paso.

#### Flujo de Trabajo
1. **Seleccionar Producto**: Buscar producto existente o crear uno nuevo
2. **Configurar Inventario**: Condición, costo de compra, precio de venta
3. **Agregar Fotos** (opcional): Imágenes específicas de la pieza
4. **Guardar**: Crea el producto (si es nuevo) y la pieza de inventario

#### Campos del Formulario

**Producto (nuevo):**
- SKU (auto-generado si se deja vacío)
- Nombre del producto
- Categoría y Marca
- Precio de venta (referencia)
- Descripción

**Inventario:**
- Condición (brand_new, misb, moc, mib, mint, loose, good, fair)
- Costo de compra
- Precio de venta individual (opcional)
- Ubicación (opcional)
- Notas

**Fotos:**
- Imágenes específicas de la pieza (se adjuntan a `piece_images`)

#### Servicio
`Collectibles::QuickAddService` maneja la lógica:
- Busca o crea el producto según parámetros
- Crea la pieza de inventario con condición y precios
- Adjunta imágenes específicas
- Actualiza estadísticas del producto

---

## 📋 Órdenes de Compra y Venta

### Órdenes de Compra (`/admin/purchase_orders`)
- Creación con líneas de productos
- Estados: Pending → In Transit → Delivered / Canceled
- Sincronización automática con inventario
- Cálculo de costos incluyendo extras

### Órdenes de Venta (`/admin/sale_orders`)
- Reserva automática de inventario
- FIFO inverso (piezas más nuevas primero)
- Gestión de pagos y envíos
- Estados de fulfillment

### Sincronización Automática
```
PurchaseOrderItem → Inventory
- Pending/In Transit → status: in_transit
- Delivered → status: available
- Canceled → status: scrap

SaleOrderItem → Inventory
- Reserva piezas available/in_transit
- Libera al reducir cantidad
```

---

## 🔌 API REST

### Endpoints v1

#### Purchase Order Items
```
POST /api/v1/purchase_order_items        # Crear item individual
POST /api/v1/purchase_order_items/batch  # Crear múltiples items
```

#### Sale Order Items
```
POST /api/v1/sale_order_items        # Crear item individual
POST /api/v1/sale_order_items/batch  # Crear múltiples items
```

#### Ejemplo de Payload (Purchase)
```json
{
  "purchase_order_item": {
    "purchase_order_id": "PO-202509-001",
    "product_sku": "SKU-1",
    "quantity": 3,
    "unit_cost": 5
  }
}
```

#### Respuestas
- `201 Created`: `{ status: "ok", id: <item_id> }`
- `422 Unprocessable`: `{ status: "error", errors: [...] }`

---

## 🛍️ Catálogo Público

### Búsqueda y Filtros (`/catalog`)
- Buscador en navbar (responsive)
- Filtros en sidebar: categorías, marcas, disponibilidad, precio
- Ordenamiento: newest, price_asc, price_desc, name_asc
- Paginación con Kaminari

### Parámetros Soportados
```
GET /catalog?q=texto&sort=price_asc&categories[]=cat1&brands[]=brand1&price_min=100&price_max=500&in_stock=1&page=2
```

---

## 🔧 Desarrollo Local

### Prerrequisitos
- Ruby 3.2.3 y Bundler
- Node.js 18+ y npm
- PostgreSQL 12+

### Instalación
```bash
# Clonar repositorio
git clone <repo-url>
cd inventory_app

# Instalar dependencias
bundle install
npm install

# Configurar base de datos
bin/rails db:create db:migrate db:seed

# Iniciar servidor
bin/dev  # Levanta Puma + esbuild watcher
```

### Compilar Assets
```bash
npm run build:watch  # Desarrollo
npm run build:prod   # Producción
```

### Variables de Entorno
```bash
COOKIE_BANNER_ENABLED=true|false
COOKIE_BANNER_TEXT="Mensaje personalizado"
COOKIE_BANNER_BUTTON_TEXT="Aceptar"
```

---

## 🧪 Testing

### TDD Workflow
```bash
# Crear branch para feature
git checkout -b feature/nueva-funcionalidad

# Ejecutar tests
bundle exec rspec

# Tests específicos
bundle exec rspec spec/services/
bundle exec rspec spec/system/
bundle exec rspec spec/requests/
```

### Factory Bot
```ruby
# Default: crea 5 unidades de inventario
product = create(:product)

# Sin inventario automático
product = create(:product, skip_seed_inventory: true)

# Cantidad personalizada
product = create(:product, seed_inventory_count: 10)
```

### N+1 Query Detection
El proyecto usa Bullet gem:
- **Desarrollo:** Alertas en navegador
- **Tests:** Fallan si se detectan N+1

---

## 📊 SEO

- Meta tags configurados en layouts
- Sitemap generado con `sitemap_generator`
- `robots.txt` apunta al sitemap

```bash
rake sitemap:generate  # Generar sitemap
```

---

## 🚀 Deployment

### Heroku
```bash
git push heroku main
heroku run rails db:migrate
```

### Verificaciones Post-Deploy
- Verificar autoload: `bin/rails zeitwerk:check`
- Verificar rutas: `bin/rails routes`
- Logs: `heroku logs --tail`

---

## 📁 Estructura del Proyecto

```
app/
├── controllers/
│   ├── admin/           # Panel de administración
│   │   ├── inventory_controller.rb
│   │   ├── inventory_locations_controller.rb
│   │   ├── inventory_adjustments_controller.rb
│   │   └── ...
│   └── ...
├── models/
│   ├── inventory.rb
│   ├── inventory_location.rb
│   ├── inventory_adjustment.rb
│   └── ...
├── services/            # Lógica de negocio
├── views/
│   └── admin/
│       └── inventory/
│           ├── index.html.erb
│           ├── transfer.html.erb
│           ├── _items.html.erb
│           ├── _location_badge.html.erb
│           └── ...
└── javascript/
    └── controllers/     # Stimulus controllers
        ├── bulk_location_assign_controller.js
        ├── inventory_transfer_controller.js
        └── ...
```

---

## 📝 Changelog Reciente

### v475 (Feb 2026)
- **Condición de pieza en Ajustes de Inventario**: Soporte para agregar productos usados/coleccionables con condiciones específicas (brand_new, misb, moc, mib, mint, loose, good, fair)
- **Precio de venta individual**: Campo `selling_price` en líneas de ajuste para piezas con precio especial
- **Quick Add Collectible** (`/admin/collectibles/quick_add`): Nueva funcionalidad para agregar coleccionables rápidamente
- **Límite de stock en frontend**: Muestra ">10" cuando hay más de 10 unidades disponibles

### v474 (Feb 2026)
- Fix: Buscador de productos en Inventory Adjustments con navegación Turbo

### v447 (Feb 2026)
- Mostrar contadores de inventario en árbol de ubicaciones
- Tabla de inventario en detalle de ubicación

### v446 (Feb 2026)
- Nueva vista de transferencia entre ubicaciones
- Panel dual origen/destino con selección múltiple

### v445 (Feb 2026)
- Edición inline de ubicación para piezas individuales
- Autocompletado de ubicaciones

### v444 (Feb 2026)
- Columna de ubicación en detalle de inventario

### v443 (Feb 2026)
- Filtros, ordenación y paginación en asignación masiva
- Carga diferida (lazy loading) de detalles

### v438-442 (Feb 2026)
- Asignación masiva de ubicación a inventario sin ubicar
- Correcciones de errores 500

---

## 📞 Soporte

Para reportar bugs o solicitar funcionalidades, crear un issue en el repositorio.

---

**Desarrollado con ❤️ para Pasatiempos**
