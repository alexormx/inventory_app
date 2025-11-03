# Purchase Order: Correcciones y Mejoras UI/UX

**Fecha:** 12 de Octubre, 2025
**Implementado por:** GitHub Copilot
**Estado:** ✅ Completado

---

## 🐛 Problema Corregido: Doble Conteo de Extras

### **Descripción del Bug**

El sistema estaba contando los costos adicionales (shipping, tax, other) **DOS VECES**:

1. **Primera vez:** Distribuidos proporcionalmente en `unit_compose_cost` y sumados en `total_line_cost`
2. **Segunda vez:** Sumados directamente al subtotal en `total_order_cost`

**Ejemplo del problema:**
```
Producto A: qty=10, unit_cost=$100
Shipping: $50
Tax: $30
Other: $20

❌ ANTES (incorrecto):
- Subtotal calculado: $1,100 (ya incluía $100 de extras distribuidos)
- Total Order Cost: $1,100 + $50 + $30 + $20 = $1,200
- Resultado: extras contados dos veces ($1,200 en vez de $1,100)

✅ AHORA (correcto):
- Subtotal: $1,000 (solo qty * unit_cost)
- Total Order Cost: $1,000 + $50 + $30 + $20 = $1,100
- Resultado: total correcto
```

---

## ✅ Correcciones Implementadas

### 1. **JavaScript (`purchase_order_items.js`)**

**Líneas 247-340:** Modificado `updateItemTotals()`

```javascript
// ❌ ANTES:
subtotal += lineTotal; // lineTotal ya incluía extras

// ✅ AHORA:
const lineBaseCost = qty * unitCost;
subtotal += lineBaseCost; // solo costo base
```

**Cambios clave:**
- Subtotal ahora solo suma `qty * unit_cost` (productos base)
- `unit_compose_cost` se sigue calculando para mostrar desglose en cada línea
- `total_line_cost` mantiene el costo compuesto (para referencia)
- Pero el **subtotal de la orden** excluye los extras

### 2. **Modelo Ruby (`purchase_order.rb`)**

**Líneas 60-72:** Modificado `recalculate_totals`

```ruby
# ❌ ANTES:
computed_subtotal = lines.sum do |li|
  (li.total_line_cost || ...).to_d  # usaba costo compuesto
end

# ✅ AHORA:
computed_subtotal = lines.sum do |li|
  qty = li.quantity.to_d
  unit_cost = li.unit_cost.to_d
  qty * unit_cost  # solo costo base
end
```

### 3. **Vista Summary (`summary.html.erb`)**

**Línea 19:** Modificado cálculo de `line_total`

```erb
<%# ❌ ANTES: %>
<% line_total = item.total_line_cost.to_d %>

<%# ✅ AHORA: %>
<% line_total = (item.quantity.to_d * item.unit_cost.to_d).round(2) %>
```

### 4. **Servicios y API** ✅ Ya estaban correctos

- `RecalculateDistributedCostsForProductService` (línea 113): ya usaba `qty * unit_cost`
- `PurchaseOrderItemsController#batch` (línea 124): ya usaba `qty * unit_cost`

---

## 🎨 Mejoras UI/UX Implementadas

### **Principios de Diseño Aplicados**

1. ✅ **Jerarquía Visual Clara:** Cards con colores diferenciados por sección
2. ✅ **Campos Calculados Destacados:** Alerts y badges en lugar de inputs planos
3. ✅ **Panel de Resumen Flotante:** Sidebar sticky con totales en tiempo real
4. ✅ **Iconografía Consistente:** Font Awesome icons para mejor escaneo
5. ✅ **Feedback Visual Inmediato:** Campos se actualizan mientras escribes
6. ✅ **Información Contextual:** Tooltips y textos de ayuda inline

---

### **Nuevos Parciales Creados**

#### 1. `_supplier_and_dates_fields.html.erb`
**Contenido:**
- Campo de proveedor con autocomplete (user-suggest)
- Estado de la orden con dropdown
- Fechas de orden, entrega esperada y entrega real
- Campo de notas expandido

**Mejoras:**
- Input groups con iconos
- Textos de ayuda contextuales
- Placeholders descriptivos

#### 2. `_costs_and_totals_fields.html.erb`
**Contenido:**
- Moneda y tipo de cambio con cálculo automático
- Costos adicionales (shipping, tax, other)
- **Subtotal destacado en alert azul** (solo productos)
- Volumen y peso total
- **Total orden en alert verde** (incluye extras)
- Total en MXN

**Mejoras:**
- Badges y alerts de colores para campos calculados
- Separación visual clara entre subtotal y total
- Explicación: "Subtotal incluye solo el costo base de los productos"
- Hidden fields sincronizados para envío al servidor

#### 3. `_summary_sidebar.html.erb`
**Contenido:**
- Panel flotante (sticky) en columna lateral
- Resumen en tiempo real de:
  - Número de productos
  - Unidades totales
  - Subtotal
  - Desglose de extras (shipping, tax, other)
  - Total orden
  - Total en MXN
- Botones de acción (Guardar/Cancelar)
- Panel informativo sobre cómo funcionan los costos

**Mejoras:**
- Header con degradado morado
- Actualización automática vía JavaScript
- Separadores visuales entre secciones
- Texto destacado para el total final

---

### **Formularios Refactorizados**

#### `new.html.erb` y `edit.html.erb`

**Estructura anterior:**
```erb
<!-- Un solo card grande, todo mezclado -->
<div class="card">
  <%= render "order_info_fields" %>
  <%= render "item_search_and_table" %>
  <!-- Botones al final -->
</div>
```

**Estructura nueva:**
```erb
<div class="row">
  <!-- Columna principal (9/12) -->
  <div class="col-lg-9">
    <!-- Sección 1: Info Básica (card azul) -->
    <div class="card bg-primary">
      <%= render "supplier_and_dates_fields" %>
    </div>

    <!-- Sección 2: Productos (card verde) -->
    <div class="card bg-success">
      <%= render "item_search_and_table" %>
    </div>

    <!-- Sección 3: Costos (card amarillo) -->
    <div class="card bg-warning">
      <%= render "costs_and_totals_fields" %>
    </div>
  </div>

  <!-- Sidebar (3/12) -->
  <div class="col-lg-3">
    <%= render "summary_sidebar" %>
  </div>
</div>
```

**Beneficios:**
- ✅ Mejor uso del espacio vertical
- ✅ Resumen siempre visible mientras haces scroll
- ✅ Separación lógica de secciones
- ✅ Colores ayudan a identificar cada área rápidamente

---

### **JavaScript Mejorado**

**Archivo:** `purchase_order_items.js`

**Función `updateItemTotals()` actualizada:**
```javascript
// Sincroniza valores calculados con múltiples elementos del DOM:

// 1. Campo hidden original (para Rails)
subtotalField.value = subtotal.toFixed(2);

// 2. Display visual (alert badge)
document.getElementById("display-subtotal").textContent = `$${subtotal.toFixed(2)}`;

// 3. Campo hidden para submit
document.getElementById("hidden_subtotal").value = subtotal.toFixed(2);

// 4. Sidebar resumen
document.getElementById("summary-subtotal").textContent = `$${subtotal.toFixed(2)}`;
```

**Función `updateTotals()` actualizada:**
- Actualiza displays de total orden
- Actualiza total en MXN
- Sincroniza sidebar con costos adicionales
- Previene loops infinitos con flag `fromTotals`

---

## 📊 Comparativa Antes/Después

| Aspecto | ❌ Antes | ✅ Ahora |
|---------|---------|----------|
| **Subtotal** | Incluía extras (incorrecto) | Solo productos base (correcto) |
| **Total Order Cost** | Contaba extras 2x | Suma correcta: subtotal + extras |
| **Visualización campos** | Inputs planos grises | Alerts de colores llamativos |
| **Organización** | Todo en un card | 3 secciones + sidebar |
| **Resumen** | Al final, fuera de vista | Sidebar flotante siempre visible |
| **Feedback** | Solo al guardar | Tiempo real mientras editas |
| **Iconografía** | Escasa | Iconos en todos los campos |
| **Ayuda contextual** | Ninguna | Tooltips y textos de ayuda |

---

## 🧪 Testing Realizado

### **Validaciones Automáticas:**
✅ Syntax check ERB (sin errores)
✅ JavaScript build exitoso (esbuild)
✅ Lint de archivos modificados (sin warnings)

### **Pruebas Manuales Sugeridas:**
- [ ] Crear nueva PO con varios productos
- [ ] Modificar shipping/tax/other y verificar que subtotal NO cambie
- [ ] Verificar que total = subtotal + extras
- [ ] Comprobar que sidebar se actualiza en tiempo real
- [ ] Editar PO existente y guardar
- [ ] Ver vista summary.html.erb de una PO
- [ ] Verificar en tabla index que totales sean correctos

---

## 📁 Archivos Modificados

### **Backend (Ruby/ERB):**
1. `app/models/purchase_order.rb` - Corrección cálculo subtotal
2. `app/views/admin/purchase_orders/new.html.erb` - Refactor con nuevos parciales
3. `app/views/admin/purchase_orders/edit.html.erb` - Refactor con nuevos parciales
4. `app/views/admin/purchase_orders/summary.html.erb` - Cálculo line_total corregido

### **Nuevos Parciales:**
5. `app/views/admin/purchase_orders/_supplier_and_dates_fields.html.erb`
6. `app/views/admin/purchase_orders/_costs_and_totals_fields.html.erb`
7. `app/views/admin/purchase_orders/_summary_sidebar.html.erb`

### **Frontend (JavaScript):**
8. `app/javascript/components/purchase_order_items.js` - Múltiples correcciones

---

## 🚀 Próximos Pasos Opcionales

### **Quick Wins Adicionales (No Implementados Aún):**

1. **Validación Inline**
   - Mostrar error si shipping < 0
   - Advertencia si exchange_rate muy alto/bajo
   - Requerir al menos 1 producto antes de guardar

2. **Barra de Progreso**
   - "Formulario 60% completo"
   - Checklist de campos requeridos

3. **Búsqueda de Productos Mejorada**
   - Preview visual con imagen
   - Mostrar stock actual
   - Soporte para escáner de códigos de barras

4. **API de Exchange Rate**
   - Botón "Obtener tipo de cambio actual"
   - Integración con API de Banxico o similar

5. **Tabla de Items Responsive**
   - Agrupar columnas con colores de fondo
   - Sticky header al hacer scroll
   - Botón "Agregar desde CSV"

6. **Shortcuts de Teclado**
   - `Ctrl+S` para guardar
   - `Ctrl+Enter` para agregar producto
   - `Esc` para cancelar

---

## 📝 Notas de Migración

### **Para desarrolladores que actualicen:**

1. **Ejecutar build de JS:**
   ```bash
   npm run build
   ```

2. **Verificar que parcial `order_info_fields` no se use más:**
   - Reemplazado por los 3 nuevos parciales
   - Si tienes customizaciones, migrarlas a los nuevos parciales

3. **Campos hidden nuevos:**
   - Los campos calculados ahora tienen versión `hidden_*` para Rails
   - El JS sincroniza automáticamente

4. **Datos existentes:**
   - **No requiere migración de DB**
   - Los totales se recalcularán correctamente al editar POs
   - Considera correr script para recalcular POs antiguas:
     ```ruby
     PurchaseOrder.find_each do |po|
       po.save # Trigger recalculate_totals callback
     end
     ```

---

## 🎯 Resumen Ejecutivo

### **Problema Crítico Resuelto:**
✅ Eliminado el doble conteo de extras (shipping/tax/other) en subtotal

### **Mejoras de UX Implementadas:**
✅ Panel de resumen flotante en sidebar
✅ Campos calculados destacados con colores
✅ Organización en secciones temáticas
✅ Feedback visual en tiempo real
✅ Iconografía y ayuda contextual

### **Impacto en Negocio:**
- 🎯 **Corrección financiera:** Totales ahora son precisos
- ⚡ **Eficiencia:** Usuarios completan órdenes más rápido
- 😊 **Satisfacción:** UI más clara y profesional
- 🐛 **Calidad:** Menos errores de captura

### **Próxima Revisión Recomendada:**
- Testing con usuarios reales (si es posible)
- Monitorear errores en Rollbar/Sentry post-deploy
- Considerar implementar quick wins adicionales según feedback

---

## 🔧 Actualización: Prevención de Doble Suma al Reabrir Purchase Orders

**Fecha:** 1 de Noviembre, 2025
**Tipo:** Bug Fix
**Estado:** ✅ Completado

### **Problema Detectado**

Al reabrir una `PurchaseOrder` existente que ya tenía costos distribuidos en sus líneas, el método `recalculate_totals` volvía a sumar los gastos de envío, impuestos y otros al total, causando duplicación:

**Escenario:**
```ruby
# PO con costos de encabezado: shipping=$30, tax=$20, other=$0
# Línea A: 2 unidades × $50 + $10 adicional distribuido = $120 (total_line_cost)
# Línea B: 1 unidad × $100 + $30 adicional distribuido = $130 (total_line_cost)

# ❌ ANTES (al reabrir/recargar):
subtotal = 250  # suma de total_line_cost (ya incluye los $50 de adicionales)
total_order_cost = 250 + 30 + 20 + 0 = 300  # ¡suma shipping/tax otra vez!

# ✅ AHORA (correcto):
subtotal = 250  # suma de total_line_cost
total_order_cost = 250  # NO vuelve a sumar porque ya están distribuidos
```

### **Raíz del Problema**

El callback `recalculate_totals` en `PurchaseOrder` siempre ejecutaba:

```ruby
# Cálculo anterior (incorrecto cuando hay distribución):
self.total_order_cost = (subtotal + shipping_cost + tax_cost + other_cost).round(2)
```

Este cálculo es correcto durante la **creación inicial** (antes de distribuir), pero incorrecto al **reabrir** una PO donde las líneas ya tienen `total_line_cost` que incluye los adicionales distribuidos.

### **Solución Implementada**

Modificado `PurchaseOrder#recalculate_totals` para detectar si los costos ya fueron distribuidos:

```ruby
# app/models/purchase_order.rb (líneas ~72-96)

def recalculate_totals
  lines = purchase_order_items.reject(&:marked_for_destruction?)

  if lines.present?
    # Subtotal base (solo unit_cost × quantity)
    base_subtotal = lines.sum do |li|
      qty = li.quantity.to_d
      unit = (li.unit_cost || 0).to_d
      (qty * unit).to_d
    end

    # Detectar si ya hay distribución aplicada
    distributed_available = lines.all? { |li|
      li.respond_to?(:total_line_cost) && li.total_line_cost.present?
    }

    distributed_subtotal = lines.sum do |li|
      (li.total_line_cost || begin
        qty = li.quantity.to_d
        unit = (li.unit_compose_cost || li.unit_cost || 0).to_d
        qty * unit
      end).to_d
    end

    # Decisión: ¿ya están distribuidos los costos en las líneas?
    if distributed_available
      # SÍ: total_line_cost ya incluye adicionales, NO volver a sumarlos
      self.subtotal = distributed_subtotal.round(2)
      self.total_order_cost = subtotal.round(2)
    else
      # NO: fase inicial o sin distribución, sumar encabezado
      self.subtotal = distributed_subtotal.round(2)
      self.total_order_cost = (base_subtotal + shipping_cost + tax_cost + other_cost).round(2)
    end

    # Volumen y peso (sin cambios)
    self.total_volume = lines.sum { |li| ... }.round(2)
    self.total_weight = lines.sum { |li| ... }.round(2)
  end

  # Total MXN (sin cambios)
  self.total_cost_mxn = if currency == 'MXN'
    total_order_cost
  else
    (total_order_cost * exchange_rate).round(2)
  end
end
```

### **Lógica de Decisión**

| Condición | `subtotal` | `total_order_cost` |
|-----------|------------|-------------------|
| **Todas las líneas tienen `total_line_cost`** (distribución aplicada) | Suma de `total_line_cost` | `subtotal` (NO suma encabezado) |
| **Algunas líneas sin `total_line_cost`** (edición inicial) | Suma calculada con fallback | `base_subtotal + shipping + tax + other` |

### **Cobertura de Pruebas**

Agregado spec en `spec/models/purchase_order_spec.rb`:

```ruby
it "does not double-count header costs when distributed line totals exist" do
  po = create(:purchase_order, user: supplier, currency: 'MXN', status: 'Pending',
              shipping_cost: 30, tax_cost: 20, other_cost: 0)

  # Líneas con distribución ya aplicada
  create(:purchase_order_item, purchase_order: po, product: product, quantity: 2,
         unit_cost: 50, unit_additional_cost: 10, unit_compose_cost: 60,
         total_line_cost: 120)
  create(:purchase_order_item, purchase_order: po, product: product, quantity: 1,
         unit_cost: 100, unit_additional_cost: 30, unit_compose_cost: 130,
         total_line_cost: 130)

  po.reload

  # Validaciones: no doble suma
  expect(po.subtotal.to_d).to eq(250)
  expect(po.total_order_cost.to_d).to eq(250)  # ← antes era 300
  expect(po.total_cost_mxn.to_d).to eq(250)
end
```

**Resultado:** 243 ejemplos, 0 fallos ✅

### **Archivos Modificados**

1. `app/models/purchase_order.rb` - Lógica condicional en `recalculate_totals`
2. `spec/models/purchase_order_spec.rb` - Nuevo test de no duplicación

### **Compatibilidad y Migración**

- ✅ **Sin cambios en esquema de DB**
- ✅ **Retrocompatible:** POs sin distribución siguen funcionando igual
- ✅ **Auto-corrección:** Al reabrir POs antiguas con distribución, se calcula correctamente

**Script opcional para regenerar totales en POs existentes:**
```ruby
# rails console
PurchaseOrder.where.not(status: 'Canceled').find_each do |po|
  po.recalculate_totals!(persist: true)
  puts "Recalculado PO #{po.id}: total_order_cost=#{po.total_order_cost}"
end
```

### **Notas para el Equipo**

- Los campos `shipping_cost`, `tax_cost`, `other_cost` en el encabezado **se mantienen para trazabilidad**, pero no afectan el total si las líneas ya tienen `total_line_cost`.
- Si se requiere re-distribuir costos (ej. cambió un precio o dimensión de producto), usar `RecalculateDistributedCostsForProductService` que regenerará `total_line_cost` y luego `recalculate_totals` usará esos valores.
- En la UI de `show.html.erb`, los gastos de encabezado se siguen mostrando por separado, pero el usuario verá que el total coincide con la suma de líneas cuando hay distribución.

---

## 🔧 Mejora de Robustez: Campo `costs_distributed_at` para Prevención Explícita de Doble Suma

**Fecha:** 2 de Noviembre, 2025
**Tipo:** Enhancement + Migration
**Estado:** ✅ Completado

### **Motivación**

La solución anterior del 1 de noviembre usaba **inferencia** para detectar si los costos ya estaban distribuidos:
```ruby
# ❌ Inferencia (frágil):
distributed_available = lines.all? { |li| li.total_line_cost.present? }
```

**Problemas con inferencia:**
- Puede fallar si alguna línea no tiene `total_line_cost` por error de datos
- No hay claridad sobre **cuándo** se distribuyeron los costos
- Difícil de auditar y debuggear
- No permite resetear la distribución fácilmente

### **Solución Implementada**

Agregamos un campo **explícito** `costs_distributed_at:datetime` a la tabla `purchase_orders`:

```ruby
# ✅ Timestamp explícito (robusto):
if costs_distributed_at.present?
  # Costos YA distribuidos → NO sumar encabezado
  self.total_order_cost = subtotal
else
  # Costos NO distribuidos → sumar base + encabezado
  self.total_order_cost = base_subtotal + shipping + tax + other
end
```

### **Beneficios**

| Aspecto | Antes (inferencia) | Ahora (timestamp) |
|---------|-------------------|-------------------|
| **Claridad** | Ambiguo | Explícito: `nil` = no distribuido, `present?` = distribuido |
| **Auditoría** | Imposible saber cuándo se distribuyó | Timestamp exacto de distribución |
| **Reseteo** | No hay forma clara de resetear | `update_column(:costs_distributed_at, nil)` |
| **Debugging** | "¿Por qué no suma?" → revisar líneas una por una | Revisar campo único `costs_distributed_at` |
| **Reportes** | N/A | Consultas como "POs distribuidas en octubre" |
| **Migración datos** | N/A | Puede popularse retroactivamente si es necesario |

### **Cambios en Código**

#### 1. Migración de Base de Datos

```ruby
# db/migrate/20251102150936_add_costs_distributed_at_to_purchase_orders.rb
class AddCostsDistributedAtToPurchaseOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :purchase_orders, :costs_distributed_at, :datetime
    add_index :purchase_orders, :costs_distributed_at
  end
end
```

**Ejecutar:**
```bash
bin/rails db:migrate
RAILS_ENV=test bin/rails db:migrate
```

#### 2. Modelo `PurchaseOrder`

```ruby
# app/models/purchase_order.rb (método recalculate_totals)

def recalculate_totals
  lines = purchase_order_items.reject(&:marked_for_destruction?)

  if lines.present?
    base_subtotal = lines.sum { |li| (li.quantity.to_d * (li.unit_cost || 0).to_d) }
    distributed_subtotal = lines.sum { |li| (li.total_line_cost || ...).to_d }

    # ✅ Decisión basada en timestamp explícito
    if costs_distributed_at.present?
      # Costos YA distribuidos → NO volver a sumar
      self.subtotal = distributed_subtotal.round(2)
      self.total_order_cost = subtotal.round(2)
    else
      # Costos NO distribuidos → sumar base + encabezado
      self.subtotal = base_subtotal.round(2)
      self.total_order_cost = (base_subtotal + shipping_cost + tax_cost + other_cost).round(2)
    end

    # ... (volumen, peso, total_cost_mxn sin cambios)
  end
end
```

#### 3. Servicio de Distribución

```ruby
# app/services/purchase_orders/recalculate_distributed_costs_for_product_service.rb

po.update_columns(
  subtotal: subtotal,
  total_volume: total_lines_volume,
  total_weight: total_lines_weight,
  total_order_cost: total_order_cost,
  total_cost_mxn: total_cost_mxn,
  costs_distributed_at: Time.current,  # ✅ Marcar como distribuido
  updated_at: Time.current
)
```

#### 4. Batch Endpoint (API)

```ruby
# app/controllers/api/v1/purchase_order_items_controller.rb

po.update!(
  subtotal: po_subtotal,
  total_volume: po_total_volume,
  total_weight: po_total_weight,
  total_order_cost: po_total_order_cost,
  total_cost_mxn: po_total_cost_mxn,
  costs_distributed_at: Time.current  # ✅ Marcar como distribuido
)
```

### **Tests Actualizados**

```ruby
# spec/models/purchase_order_spec.rb

it "does not double-count header costs when distributed line totals exist" do
  po = create(:purchase_order, shipping_cost: 30, tax_cost: 20)
  create(:purchase_order_item, purchase_order: po, total_line_cost: 120)
  create(:purchase_order_item, purchase_order: po, total_line_cost: 130)

  # ✅ Marcar explícitamente como distribuido
  po.update_column(:costs_distributed_at, Time.current)
  po.recalculate_totals!
  po.reload

  expect(po.subtotal.to_d).to eq(250)
  expect(po.total_order_cost.to_d).to eq(250)  # NO suma shipping/tax
end

it "sums header costs when costs_distributed_at is nil" do
  po = create(:purchase_order, shipping_cost: 30, tax_cost: 20, costs_distributed_at: nil)
  create(:purchase_order_item, purchase_order: po, quantity: 2, unit_cost: 50)

  po.reload

  expect(po.subtotal.to_d).to eq(100)
  expect(po.total_order_cost.to_d).to eq(150)  # SÍ suma shipping/tax
end
```

**Resultado:** 244 ejemplos, 0 fallos ✅

### **Archivos Modificados**

1. `db/migrate/20251102150936_add_costs_distributed_at_to_purchase_orders.rb` - Nueva migración
2. `app/models/purchase_order.rb` - Lógica basada en timestamp
3. `app/services/purchase_orders/recalculate_distributed_costs_for_product_service.rb` - Setea timestamp
4. `app/controllers/api/v1/purchase_order_items_controller.rb` - Setea timestamp en batch
5. `spec/models/purchase_order_spec.rb` - Tests con ambos escenarios

### **Uso en Consola**

```ruby
# Ver POs con costos distribuidos
PurchaseOrder.where.not(costs_distributed_at: nil)

# Ver POs pendientes de distribuir
PurchaseOrder.where(costs_distributed_at: nil)

# Re-distribuir costos de una PO (resetear primero)
po = PurchaseOrder.find('PO-202511-001')
po.update_column(:costs_distributed_at, nil)
PurchaseOrders::RecalculateDistributedCostsForProductService.new(po.products.first).call

# Forzar recalculo después de editar manualmente
po.recalculate_totals!(persist: true)
```

### **Compatibilidad Retroactiva**

- ✅ **POs existentes:** `costs_distributed_at` será `nil` → totales calculan con suma de encabezado (comportamiento original)
- ✅ **Nuevas distribuciones:** Servicios y API setean el timestamp automáticamente
- ✅ **Sin breaking changes:** Si no se distribuyen costos, funciona igual que antes

### **Notas para el Equipo**

1. **Al editar manualmente una PO:**
   - Si `costs_distributed_at` está presente y editas shipping/tax/other, considera resetear el flag a `nil` para que se redistribuya.

2. **Para re-distribuir costos:**
   ```ruby
   # Opción A: resetear flag y recalcular
   po.update_column(:costs_distributed_at, nil)
   po.recalculate_totals!(persist: true)

   # Opción B: usar servicio (recomendado para cambios de dimensiones)
   PurchaseOrders::RecalculateDistributedCostsForProductService.new(product).call
   ```

3. **Reportes sugeridos:**
   - POs con costos no distribuidos (pendientes de procesamiento)
   - POs distribuidas por mes (auditoría)

---

**Fin del documento** 🎉

````
