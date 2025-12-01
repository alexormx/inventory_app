# Lógica de `costs_distributed_at` en Purchase Orders

## Resumen Ejecutivo

El campo `costs_distributed_at` (tipo `datetime`) controla cómo se calculan los totales de una Purchase Order (PO). Es un **timestamp explícito** que indica si los costos adicionales (shipping, tax, other) ya fueron distribuidos proporcionalmente en las líneas (`purchase_order_items`) o no.

### Estados Posibles

| Estado | Valor | Significado | Comportamiento en Totales |
|--------|-------|-------------|---------------------------|
| **No Distribuido** | `nil` | Los costos adicionales NO están en las líneas | `total_order_cost = base_subtotal + shipping + tax + other` |
| **Distribuido** | `timestamp` | Los costos adicionales YA están incluidos en `total_line_cost` | `total_order_cost = distributed_subtotal` (sin sumar headers) |

---

## ¿Cuándo se Establece `costs_distributed_at`?

### 1. **Creación Batch de Items con Distribución** (API Endpoint)

**Archivo:** `app/controllers/api/v1/purchase_order_items_controller.rb`
**Método:** `batch`

Cuando se crean múltiples items via API con costos ya distribuidos:

```ruby
POST /api/v1/purchase_order_items/batch
{
  "purchase_order_id": "PO-2025-11-001",
  "items": [
    { "product_id": 123, "quantity": 10, "unit_cost": 50 },
    { "product_id": 456, "quantity": 5, "unit_cost": 100 }
  ]
}
```

**Qué hace:**
1. Calcula volumen total de todas las líneas
2. Distribuye `shipping_cost + tax_cost + other_cost` proporcionalmente por volumen
3. Calcula `unit_additional_cost`, `unit_compose_cost`, `total_line_cost` para cada línea
4. **Establece `costs_distributed_at = Time.current`**
5. Actualiza totales de la PO usando los costos distribuidos

### 2. **Servicio de Recálculo de Costos Distribuidos**

**Archivo:** `app/services/purchase_orders/recalculate_distributed_costs_for_product_service.rb`
**Método:** `call`

Cuando se recalculan costos distribuidos para un producto específico:

```ruby
service = PurchaseOrders::RecalculateDistributedCostsForProductService.new(product)
service.call
```

**Qué hace:**
1. Encuentra todas las POs que tienen items del producto
2. Para cada PO:
   - Recalcula volúmenes/pesos basándose en dimensiones actuales
   - Redistribuye costos adicionales proporcionalmente
   - Actualiza `total_line_cost` en cada item
   - **Establece `costs_distributed_at = Time.current`**
   - Propaga costos a inventarios individuales

### 3. **Rake Task de Marcado Masivo**

**Archivo:** `lib/tasks/purchase_orders.rake`
**Task:** `purchase_orders:mark_distributed_costs`

Para marcar POs existentes que ya tienen costos distribuidos:

```bash
# Dry run (solo reporte)
DRY_RUN=1 bin/rails purchase_orders:mark_distributed_costs

# Aplicar cambios
bin/rails purchase_orders:mark_distributed_costs
```

**Criterios de detección:**
- Todas las líneas tienen `total_line_cost` presente
- La suma de `total_line_cost` coincide con `total_order_cost` o `subtotal` (tolerancia ±0.01)

**Qué hace:**
- **Establece `costs_distributed_at = po.updated_at`** (usa fecha histórica de última modificación)

---

## ¿Cuándo se LIMPIA `costs_distributed_at`?

El timestamp se invalida automáticamente cuando los datos cambian, porque los costos distribuidos ya no son válidos.

### 1. **Cambios en Costos de Encabezado** (Callback en PurchaseOrder)

**Archivo:** `app/models/purchase_order.rb`
**Callback:** `before_validation :clear_distributed_timestamp_if_headers_changed`

```ruby
def clear_distributed_timestamp_if_headers_changed
  if costs_distributed_at.present? && (
    will_save_change_to_shipping_cost? ||
    will_save_change_to_tax_cost? ||
    will_save_change_to_other_cost?
  )
    self.costs_distributed_at = nil
  end
end
```

**Ejemplo:**
```ruby
po = PurchaseOrder.find("PO-2025-11-001")
po.costs_distributed_at  # => 2025-11-03 10:30:00
po.shipping_cost = 500   # Cambiar shipping
po.save                  # costs_distributed_at se limpia automáticamente → nil
```

### 2. **Cambios en Items de la PO** (Callback en PurchaseOrderItem)

**Archivo:** `app/models/purchase_order_item.rb`
**Callback:** `after_commit :recalculate_parent_order_totals`

```ruby
def recalculate_parent_order_totals
  return unless purchase_order_id.present?
  po = PurchaseOrder.find_by(id: purchase_order_id)
  return unless po

  # Si hay cambios en items y la PO tenía costos distribuidos, limpiar
  if po.costs_distributed_at.present?
    po.update_column(:costs_distributed_at, nil)
  end

  po.recalculate_totals!(persist: true)
end
```

**Situaciones que lo disparan:**
- Cambiar cantidad de un item existente
- Agregar nuevos items a la PO
- Eliminar items de la PO
- Cambiar `unit_cost` de un item

**Ejemplo:**
```ruby
po = PurchaseOrder.find("PO-2025-11-001")
po.costs_distributed_at  # => 2025-11-03 10:30:00

item = po.purchase_order_items.first
item.quantity = 20       # Cambiar cantidad
item.save                # costs_distributed_at se limpia automáticamente → nil
```

---

## Cómo Afecta el Cálculo de Totales

**Archivo:** `app/models/purchase_order.rb`
**Método:** `recalculate_totals`

### Caso 1: `costs_distributed_at` es `nil` (No distribuido)

```ruby
# Subtotal base (solo unit_cost × quantity, sin adicionales)
base_subtotal = lines.sum { |li| li.quantity * li.unit_cost }

self.subtotal = base_subtotal
self.total_order_cost = base_subtotal + shipping_cost + tax_cost + other_cost
```

**Ejemplo:**
```
Item 1: 10 × $50 = $500
Item 2: 5 × $100 = $500
base_subtotal = $1,000

shipping_cost = $200
tax_cost = $100
other_cost = $50

total_order_cost = $1,000 + $200 + $100 + $50 = $1,350
```

### Caso 2: `costs_distributed_at` presente (Distribuido)

```ruby
# Subtotal distribuido (con total_line_cost)
distributed_subtotal = lines.sum { |li| li.total_line_cost }

self.subtotal = distributed_subtotal
self.total_order_cost = distributed_subtotal  # NO suma headers
```

**Ejemplo:**
```
Item 1: total_line_cost = $660  (incluye $60 de shipping distribuido)
Item 2: total_line_cost = $690  (incluye $90 de shipping distribuido)
distributed_subtotal = $1,350

total_order_cost = $1,350  (sin volver a sumar shipping/tax/other)
```

---

## Flujo de Vida Completo: Ejemplo Práctico

### Escenario 1: Creación Normal (Sin Distribución)

```ruby
# 1. Crear PO
po = PurchaseOrder.create!(
  order_date: Date.today,
  expected_delivery_date: Date.today + 30.days,
  shipping_cost: 200,
  tax_cost: 100,
  other_cost: 50
)
po.costs_distributed_at  # => nil

# 2. Agregar items manualmente
po.purchase_order_items.create!(product_id: 123, quantity: 10, unit_cost: 50)
po.purchase_order_items.create!(product_id: 456, quantity: 5, unit_cost: 100)

# 3. Recalcular totales (automático via callback)
po.reload
po.subtotal           # => 1000.0
po.total_order_cost   # => 1350.0 (1000 + 200 + 100 + 50)
po.costs_distributed_at  # => nil (sigue sin distribuir)
```

### Escenario 2: Creación con Distribución (API Batch)

```ruby
# 1. POST /api/v1/purchase_order_items/batch
# El endpoint distribuye automáticamente

po.reload
po.costs_distributed_at  # => 2025-11-03 10:30:00 (timestamp establecido)
po.subtotal           # => 1350.0 (distributed_subtotal)
po.total_order_cost   # => 1350.0 (sin sumar headers)

# 2. Ver items con costos distribuidos
item1 = po.purchase_order_items.first
item1.unit_cost              # => 50.0
item1.unit_additional_cost   # => 6.0
item1.unit_compose_cost      # => 56.0
item1.total_line_cost        # => 560.0
```

### Escenario 3: Edición Invalida Distribución

```ruby
# PO con costos distribuidos
po.costs_distributed_at  # => 2025-11-03 10:30:00

# Cambiar shipping cost
po.update(shipping_cost: 300)

# Automáticamente se limpia el timestamp
po.costs_distributed_at  # => nil

# Ahora recalcula con el modelo tradicional
po.total_order_cost   # => 1450.0 (1000 + 300 + 100 + 50)
```

### Escenario 4: Re-Distribución Manual

```ruby
# Después de editar, volver a distribuir
service = PurchaseOrders::RecalculateDistributedCostsForProductService.new(product)
service.call

po.reload
po.costs_distributed_at  # => 2025-11-03 11:00:00 (nuevo timestamp)
po.total_order_cost   # => 1450.0 (ahora distribuido con nuevo shipping)
```

---

## Herramientas de Mantenimiento

### 1. Admin UI para Marcar POs Distribuidas

**Ubicación:** `/admin/settings`
**Controlador:** `Admin::SettingsController#mark_distributed_costs`

**Características:**
- Modo dry-run (solo reporte) o apply (aplicar cambios)
- Tolerancia configurable para comparación de flotantes (default: 0.01)
- Guarda ejecución en `MaintenanceRun` para auditoría
- Muestra muestra de candidatas y omitidas

**Uso:**
1. Ir a Admin → Settings
2. Buscar tarjeta "Marcar POs con Costos Distribuidos"
3. Seleccionar "Dry Run: Sí" primero para ver reporte
4. Revisar resultados en tabla de MaintenanceRuns
5. Si es correcto, ejecutar con "Dry Run: No" para aplicar

### 2. Indicador Visual en Vista de PO

**Ubicación:** `/admin/purchase_orders/:id`

**Elementos visuales:**

1. **Badge en Header:**
   ```html
   <span class="badge bg-success" title="Distribuido el 2025-11-03 10:30">
     ✓ Costos Distribuidos
   </span>
   ```

2. **Alert Informativo:**
   ```
   ℹ️ Esta orden tiene costos distribuidos (shipping, tax, other) incluidos
   en cada línea desde 2025-11-03 10:30. Los totales reflejan estos costos
   sin sumar nuevamente los encabezados.
   ```

---

## Consideraciones Técnicas

### 1. Callbacks y Orden de Ejecución

```
PurchaseOrderItem cambios → after_commit → recalculate_parent_order_totals
  ↓
  PurchaseOrder.update_column(:costs_distributed_at, nil)
  ↓
  PurchaseOrder.recalculate_totals!(persist: true)
    ↓
    before_validation → clear_distributed_timestamp_if_headers_changed
    ↓
    before_validation → recalculate_totals
    ↓
    save
```

### 2. Uso de `update_column` vs `update`

En `recalculate_parent_order_totals` se usa `update_column` para evitar callbacks infinitos:

```ruby
po.update_column(:costs_distributed_at, nil)  # Sin callbacks
po.recalculate_totals!(persist: true)         # Llamada explícita
```

### 3. Tolerancia en Detección

El rake task usa tolerancia de 0.01 por defecto para evitar problemas de precisión flotante:

```ruby
sum_total_line_cost = lines.sum { |li| li.total_line_cost.to_f }
matches_total = (sum_total_line_cost - po.total_order_cost.to_f).abs <= tolerance
matches_subtotal = (sum_total_line_cost - po.subtotal.to_f).abs <= tolerance
```

### 4. Timestamp Histórico vs Actual

- **API/Service:** usan `Time.current` (momento de distribución)
- **Rake task:** usa `po.updated_at` (referencia histórica para POs antiguas)

---

## Diagnóstico y Troubleshooting

### ¿Cómo saber si una PO tiene costos distribuidos?

```ruby
po = PurchaseOrder.find("PO-2025-11-001")

if po.costs_distributed_at.present?
  puts "✓ Costos distribuidos desde #{po.costs_distributed_at}"
  puts "  Subtotal: #{po.subtotal}"
  puts "  Total: #{po.total_order_cost} (sin sumar headers)"
else
  puts "✗ Costos NO distribuidos"
  puts "  Base subtotal: #{po.subtotal}"
  puts "  Shipping: #{po.shipping_cost}"
  puts "  Tax: #{po.tax_cost}"
  puts "  Other: #{po.other_cost}"
  puts "  Total: #{po.total_order_cost} (base + headers)"
end
```

### ¿Por qué mi PO perdió la distribución?

Chequear si hubo cambios:

```ruby
po.previous_changes  # Ver qué cambió en último save
po.purchase_order_items.map(&:previous_changes)  # Ver cambios en items
```

Causas comunes:
- Cambio en `shipping_cost`, `tax_cost`, `other_cost`
- Cambio en cantidad de items
- Agregado/eliminado items
- Cambio en `unit_cost` de items

### ¿Cómo redistribuir después de editar?

```ruby
# Opción 1: Servicio para un producto específico
product = Product.find(123)
service = PurchaseOrders::RecalculateDistributedCostsForProductService.new(product)
result = service.call

# Opción 2: Usar API batch endpoint para recrear items con distribución
# (requiere eliminar items existentes y volver a crearlos)

# Opción 3: Marcar manualmente si los costos ya están correctos
po.update(costs_distributed_at: Time.current)
```

---

## Tests de Comportamiento

**Archivo:** `spec/models/purchase_order_spec.rb`

### Test 1: Costos No Distribuidos (nil)

```ruby
it 'calculates totals with headers when costs_distributed_at is nil' do
  po = create(:purchase_order,
    shipping_cost: 100, tax_cost: 50, other_cost: 30,
    costs_distributed_at: nil
  )
  create(:purchase_order_item, purchase_order: po, quantity: 10, unit_cost: 50)

  po.reload
  expect(po.costs_distributed_at).to be_nil
  expect(po.subtotal).to eq(500.0)
  expect(po.total_order_cost).to eq(680.0)  # 500 + 100 + 50 + 30
end
```

### Test 2: Costos Distribuidos (presente)

```ruby
it 'uses distributed subtotal when costs_distributed_at is present' do
  po = create(:purchase_order,
    shipping_cost: 100, tax_cost: 50, other_cost: 30,
    costs_distributed_at: Time.current
  )
  create(:purchase_order_item, purchase_order: po,
    quantity: 10, unit_cost: 50, total_line_cost: 680
  )

  po.reload
  expect(po.costs_distributed_at).to be_present
  expect(po.subtotal).to eq(680.0)
  expect(po.total_order_cost).to eq(680.0)  # Sin sumar headers
end
```

### Test 3: Limpieza al Cambiar Headers

```ruby
it 'clears costs_distributed_at when header costs change' do
  po = create(:purchase_order,
    shipping_cost: 100,
    costs_distributed_at: Time.current
  )

  po.update(shipping_cost: 200)
  expect(po.costs_distributed_at).to be_nil
end
```

### Test 4: Limpieza al Cambiar Items

```ruby
it 'clears costs_distributed_at when items change' do
  po = create(:purchase_order, costs_distributed_at: Time.current)
  item = create(:purchase_order_item, purchase_order: po, quantity: 10)

  item.update(quantity: 20)
  po.reload
  expect(po.costs_distributed_at).to be_nil
end
```

---

## Resumen de Responsabilidades

| Componente | Responsabilidad |
|------------|-----------------|
| `PurchaseOrder#recalculate_totals` | Decidir qué fórmula usar basándose en `costs_distributed_at` |
| `PurchaseOrder#clear_distributed_timestamp_if_headers_changed` | Limpiar timestamp si cambian shipping/tax/other |
| `PurchaseOrderItem#recalculate_parent_order_totals` | Limpiar timestamp si cambian items |
| `RecalculateDistributedCostsForProductService` | Distribuir costos y establecer timestamp |
| `Api::V1::PurchaseOrderItemsController#batch` | Crear items con distribución y establecer timestamp |
| `purchase_orders:mark_distributed_costs` | Detectar y marcar POs con costos ya distribuidos |
| Admin UI `/admin/settings` | Interfaz para ejecutar detección con dry-run |
| Vista PO `/admin/purchase_orders/:id` | Mostrar estado de distribución visualmente |

---

## Changelog

| Fecha | Cambio |
|-------|--------|
| 2025-11-02 | Implementación inicial de `costs_distributed_at` |
| 2025-11-03 | Agregada lógica de limpieza automática en cambios |
| 2025-11-03 | Agregado rake task y admin UI para marcado masivo |
| 2025-11-03 | Agregados indicadores visuales en vista de PO |
