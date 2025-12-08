# RSwag Testing Strategy

Fecha: 2025-12-07

Resumen: Para estabilizar los ejemplos de API generados con rswag (escrituras sobre `/api/v1/sale_order_items` y `/batch`), se aplicó una estrategia de pruebas que evita abortos transaccionales (`PG::InFailedSqlTransaction`) y notificaciones de Bullet durante estos ejemplos.

## Cambios clave

- `spec/rails_helper.rb`
  - Hook `around(:each, :rswag)`: desactiva Bullet y ejecuta cada ejemplo rswag dentro de una transacción manual, con `rollback` al finalizar para una limpieza segura.
  - Objetivo: aislar efectos de FactoryBot/callbacks y evitar conflictos con el manejo transaccional de rswag.

- `spec/requests/api/v1/swagger/sale_order_items_spec.rb`
  - Se eliminó `skip` en respuestas 201/422 y se añadió metadata `rswag: true` para activar el hook.
  - Se corrigió el esquema de la respuesta del endpoint batch: `created` ahora se valida como `Array<Integer>` (IDs), consistente con la implementación del controlador.

## Razonamiento

- Los ejemplos con rswag combinan generación de documentación, ejecución de controladores y factories. Bajo transacciones automáticas de RSpec pueden quedar conexiones en estado abortado.
- Desactivar Bullet durante estos ejemplos evita que las notificaciones de N+1 (optimización) interfieran con la consistencia de la prueba.
- El `rollback` al final garantiza una base de datos limpia sin depender de truncación global.

## Resultados

- Suite completa: 262 ejemplos, 0 fallos.
- RSwag: 4 ejemplos, 0 fallos.

## Consideraciones futuras

- Mantener `:rswag` como metadata en nuevos specs swagger.
- Alinear los esquemas OpenAPI con las respuestas reales de los controladores.
- En endpoints de escritura intensiva, considerar desactivar Bullet vía `around_action` en el controlador (ya aplicado en `SaleOrderItemsController`).
