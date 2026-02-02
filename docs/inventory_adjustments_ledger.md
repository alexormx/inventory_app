## Inventory Adjustments Ledger

### Resumen
Módulo para registrar correcciones manuales de inventario: altas (increase) y bajas (decrease) con estados y trazabilidad pieza a pieza.

### Modelos
- `InventoryAdjustment`: cabecera (draft/applied) + referencia `ADJ-YYYYMM-NN`.
- `InventoryAdjustmentLine`: líneas con `direction`, `quantity`, `reason`, `unit_cost`, `item_condition`, `selling_price`.
- `InventoryAdjustmentEntry`: bitácora por item (`created`, `marked_scrap`, `marked_damaged`, etc.).

### Estados
`draft` → editable. `applied` → inmutable (sólo reversible).

### Condición de Pieza (item_condition)
Para líneas de tipo `increase`, se puede especificar la condición del inventario a crear:

| Valor | Descripción |
|-------|-------------|
| `brand_new` | Nuevo sellado (default) |
| `misb` | Mint In Sealed Box |
| `moc` | Mint On Card |
| `mib` | Mint In Box |
| `mint` | Mint (sin empaque) |
| `loose` | Suelto |
| `good` | Buen estado |
| `fair` | Aceptable |

El enum está definido tanto en `Inventory` como en `InventoryAdjustmentLine` usando la misma constante `Inventory::ITEM_CONDITIONS`.

### Precio de Venta Individual (selling_price)
Campo opcional en `InventoryAdjustmentLine` que se propaga a `Inventory.selling_price` al aplicar el ajuste. Útil para piezas coleccionables con valor especial diferente al precio estándar del producto.

### Aplicar
Servicio: `ApplyInventoryAdjustmentService`:
1. Genera referencia si falta.
2. Valida stock suficiente sumando decreases por producto.
3. Increases: crea `Inventory` status `available` con:
   - `item_condition`: de la línea o `brand_new` por defecto
   - `selling_price`: de la línea si está presente
4. Decreases: selecciona FIFO y cambia estado según razón.
5. Crea `InventoryAdjustmentEntry` por cada acción.

### Razones de Decrease
`scrap`, `marketing`, `lost`, `damaged` → mapean a estados homónimos (marketing, lost, damaged; scrap conserva scrap).

### Referencia
Secuencia mensual `ADJ-YYYYMM-NN` (NN inicia en 01). Generación idempotente: sólo si `reference` está vacío al aplicar.

### Campos Extra
`inventories.adjustment_reference` almacena la referencia del ajuste que la creó o modificó.

### UI del Formulario
El formulario de ajustes (`/admin/inventory_adjustments/new`) incluye:
- Buscador de productos con autocompletado
- Selector de dirección (Increase/Decrease)
- Campo de cantidad
- **Selector de condición** (visible solo para Increase)
- **Campo de precio de venta** (visible solo para Increase)
- Selector de razón (visible solo para Decrease)
- Campo de costo unitario
- Campo de nota

La visibilidad de campos se maneja dinámicamente con JavaScript según la dirección seleccionada.

### Reversión (outline)
`ReverseInventoryAdjustmentService` (no detallado): revertirá estados y eliminará los inventarios creados. Pendiente de documentación ampliada.

### Posibles Variables de Sistema Futuras
`INVENTORY_ADJ_REFERENCE_PATTERN` (default `ADJ-YYYYMM`) para customizar prefijo/patrón.
`INVENTORY_ADJ_ALLOW_MULTI_LINES` boolean (default true).

### Testing
Ver specs:
- `spec/models/inventory_adjustment_reference_spec.rb`
- `spec/services/apply_inventory_adjustment_service_reference_spec.rb`
- `spec/services/apply_inventory_adjustment_multiple_lines_same_product_spec.rb`

### Próximos pasos sugeridos
- UI para reverse.
- Filtros por razón y estado resultante.
- Export CSV de ledger.
- Auditoría diffs (before/after snapshot).

