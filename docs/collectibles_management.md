# Gestión de Coleccionables y Productos Usados

## Resumen
El sistema soporta productos coleccionables y usados con condiciones específicas y precios individuales por pieza. Esto permite vender productos únicos como figuras vintage, juguetes descatalogados, o piezas abiertas/usadas con precios diferenciados.

## Condiciones de Inventario (item_condition)

### Enum Values
```ruby
Inventory::ITEM_CONDITIONS = {
  brand_new: 0,  # Nuevo sellado
  misb: 1,       # Mint In Sealed Box
  moc: 2,        # Mint On Card
  mib: 3,        # Mint In Box
  mint: 4,       # Mint (sin empaque)
  loose: 5,      # Suelto
  good: 6,       # Buen estado
  fair: 7        # Aceptable
}
```

### Etiquetas Humanas
```ruby
Inventory::CONDITION_LABELS = {
  brand_new: "Nuevo (Sellado)",
  misb: "MISB - Mint In Sealed Box",
  moc: "MOC - Mint On Card",
  mib: "MIB - Mint In Box",
  mint: "Mint",
  loose: "Loose (Suelto)",
  good: "Good (Buen estado)",
  fair: "Fair (Aceptable)"
}
```

## Formas de Agregar Coleccionables

### 1. Via Ajustes de Inventario
**URL**: `/admin/inventory_adjustments/new`

Ideal para agregar múltiples piezas de productos existentes:

1. Buscar el producto en el buscador
2. Seleccionar dirección `Increase`
3. Especificar cantidad
4. **Seleccionar condición** (dropdown)
5. Opcionalmente agregar **precio de venta individual**
6. Guardar y aplicar el ajuste

**Ventajas**:
- Múltiples productos en un solo ajuste
- Trazabilidad completa con referencia ADJ-YYYYMM-NN
- Historial de quién y cuándo se agregó

### 2. Via Quick Add Collectible
**URL**: `/admin/collectibles/quick_add`

Ideal para agregar un producto nuevo o existente con inventario en un solo paso:

1. **Seleccionar tipo de producto**:
   - Producto existente: buscar por nombre/SKU
   - Producto nuevo: llenar datos básicos

2. **Configurar inventario**:
   - Condición
   - Costo de compra
   - Precio de venta individual (opcional)
   - Ubicación (opcional)
   - Notas

3. **Agregar fotos** (opcional):
   - Imágenes específicas de la pieza
   - Se guardan en `piece_images` del inventario

**Ventajas**:
- Un solo formulario para todo
- Crear producto nuevo sobre la marcha
- Fotos específicas de la pieza

## Precio de Venta Individual (selling_price)

### En Inventario
El modelo `Inventory` tiene un campo `selling_price` que permite:
- Precio específico para esa pieza
- Si es `nil`, se usa el precio del producto (`product.selling_price`)

### En Catálogo
El frontend muestra las piezas agrupadas por condición:
- Cada condición muestra su precio (individual o del producto)
- El cliente puede agregar al carrito especificando la condición

### Lógica de Precio
```ruby
def effective_price
  selling_price.presence || product.selling_price
end
```

## Fotos de Pieza (piece_images)

### Modelo
```ruby
class Inventory < ApplicationRecord
  has_many_attached :piece_images
end
```

### Uso
Las fotos de pieza se usan para:
- Mostrar el estado real de un coleccionable usado
- Diferenciar piezas del mismo producto
- Dar confianza al comprador sobre la condición

## Visualización en Frontend

### Página de Producto
Para productos con coleccionables (diferentes condiciones):
- Lista todas las condiciones disponibles
- Muestra precio por condición
- Indica cantidad disponible por condición
- Link a glosario de condiciones

### Carrito
Al agregar al carrito:
- Se especifica la condición deseada
- Se reserva una pieza específica de esa condición
- Se muestra la condición en el resumen

## Servicios

### Collectibles::QuickAddService
```ruby
# Parámetros
{
  use_existing_product: '0' | '1',
  existing_product_id: integer,
  product: {
    product_sku, product_name, category, brand, selling_price, description
  },
  inventory: {
    item_condition, purchase_cost, selling_price, inventory_location_id, notes
  }
}

# Retorno
{
  success: true/false,
  message: string,
  errors: [],
  product: Product,
  inventory: Inventory
}
```

### ApplyInventoryAdjustmentService
Actualizado para soportar:
- `item_condition` en líneas de increase
- `selling_price` en líneas de increase

## Base de Datos

### Tabla inventories
```ruby
- item_condition: integer (enum, default: 0)
- selling_price: decimal (nullable)
- piece_images: via ActiveStorage
```

### Tabla inventory_adjustment_lines
```ruby
- item_condition: integer (enum, default: 0)
- selling_price: decimal (nullable)
```

## Próximos Pasos Sugeridos

- Galería de fotos de pieza en detalle de inventario
- Filtro por condición en catálogo
- Reporte de coleccionables
- Alertas de precio de mercado
- Integración con plataformas de coleccionables
