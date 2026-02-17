# Troubleshooting: eliminar ítems de Sale Order

## Síntoma
Al intentar eliminar una línea de una SO desde edición, la acción no se completa y aparece error en el guardado.

## Causa común
Existe una referencia activa en `inventory_assignment_logs.sale_order_item_id` hacia la línea que se intenta eliminar.

## Solución aplicada
- El modelo `SaleOrderItem` ahora usa `has_many :inventory_assignment_logs, dependent: :nullify`.
- Esto conserva el historial de auditoría y evita violaciones de llave foránea al destruir la línea.

## Verificación rápida (producción)
```bash
heroku run rails runner "id=11258; puts InventoryAssignmentLog.where(sale_order_item_id: id).count"
```

## Nota
Si la línea tiene inventario en estado `sold`, la eliminación seguirá bloqueada por regla de negocio (comportamiento esperado).
