# Ubicaciones de Inventario (Warehouse Management)

## Resumen
Sistema de ubicaciones jerárquico para organizar el almacén. Permite asignar piezas de inventario a ubicaciones específicas, transferir entre ubicaciones, y visualizar el inventario por ubicación.

## Modelo de Datos

### InventoryLocation
```ruby
# Campos principales
- name: string (nombre de la ubicación)
- location_type: string (warehouse, section, shelf, level, position)
- parent_id: integer (referencia a ubicación padre, self-referential)
- path_cache: string (ruta denormalizada para performance)
- active: boolean (si está activa o deshabilitada)
```

### LocationType
Configura los tipos de ubicación disponibles:
- `warehouse` - Bodega principal
- `section` - Sección dentro de bodega
- `shelf` - Estante
- `level` - Nivel del estante
- `position` - Posición específica

### Inventory
```ruby
- inventory_location_id: integer (nullable, referencia a InventoryLocation)
```

## Rutas y Vistas

### Vista de Árbol (`/admin/inventory_locations`)
- Estructura jerárquica expandible/colapsable
- Contadores de inventario por nivel:
  - **Directo**: piezas asignadas directamente a esta ubicación
  - **Total**: piezas en esta ubicación + todas las sub-ubicaciones
- Acciones: editar, eliminar, agregar hijo

### Detalle de Ubicación (`/admin/inventory_locations/:id`)
- Información de la ubicación
- Breadcrumb de ancestros
- Tabla de inventario asignado a esta ubicación
- Sub-ubicaciones hijas

### Inventario Sin Ubicar (`/admin/inventory/unlocated`)
Asignación masiva de ubicación a piezas sin asignar:
- Filtro por nombre/SKU de producto
- Ordenación por nombre o cantidad
- Paginación (20 productos por página)
- Carga diferida de detalles (AJAX)
- Selección múltiple con cantidades personalizadas
- Búsqueda de ubicación destino con autocompletado

### Transferencia (`/admin/inventory/transfer`)
Mover piezas entre ubicaciones:
- Panel dual: origen y destino
- Selección de ubicación con autocompletado
- Carga AJAX del inventario por ubicación
- Selección múltiple de piezas
- Validación de ubicaciones diferentes
- Transferencia instantánea

### Edición Inline
En el detalle de inventario de cada producto:
- Botón de lápiz (✏️) junto a la ubicación
- Modal con búsqueda de ubicación
- Opción de quitar ubicación
- Solo disponible para piezas `available` o `reserved`

## Controladores

### Admin::InventoryLocationsController
```ruby
# Acciones principales
- index: árbol de ubicaciones con contadores
- show: detalle con inventario y sub-ubicaciones
- new/create: crear ubicación
- edit/update: editar ubicación
- destroy: eliminar (solo si no tiene hijos ni inventario)
```

### Admin::InventoryController
```ruby
# Acciones de ubicación
- unlocated: vista de asignación masiva
- unlocated_product_items: AJAX para detalles de producto
- bulk_assign_location: asignación masiva POST
- transfer: vista de transferencia
- transfer_location_items: AJAX para items de ubicación
- perform_transfer: ejecutar transferencia POST
- update_location: actualizar ubicación de pieza individual
```

## Stimulus Controllers

### bulk-location-assign
Maneja la asignación masiva:
- Carga diferida de detalles por producto
- Selección múltiple de piezas
- Validación de cantidades
- Búsqueda de ubicación destino

### inventory-transfer
Maneja la transferencia:
- Selección de ubicaciones origen/destino
- Carga de inventario por ubicación
- Selección de piezas a transferir
- Validación y submit

### location-suggest
Autocompletado de ubicaciones:
- Búsqueda por nombre
- Muestra ruta completa (full_path)
- Selección con teclado o click

### inventory-locations
Manejo del árbol:
- Expandir/colapsar nodos
- Navegación jerárquica

## Métodos del Modelo InventoryLocation

```ruby
# Ruta completa
location.full_path  # => "Bodega Principal > Estante A > Nivel 1"

# Ancestros
location.ancestors  # => [parent, grandparent, ...]

# Descendientes
location.descendants  # => [children, grandchildren, ...]

# Conteo de inventario
location.inventory_count  # => número de piezas directas
location.total_inventory_count  # => piezas directas + sub-ubicaciones
```

## Consideraciones de Performance

- `path_cache` almacena la ruta denormalizada para evitar queries recursivos
- Usar `includes(:inventory_location)` en queries de inventario
- Los contadores se calculan en la vista, considerar denormalizar si hay problemas de performance

## Próximos Pasos Sugeridos

- Contador denormalizado en InventoryLocation
- Barcode/QR para escaneo de ubicaciones
- Sugerencia automática de ubicación basada en producto
- Restricciones de capacidad por ubicación
- Historial de movimientos entre ubicaciones
