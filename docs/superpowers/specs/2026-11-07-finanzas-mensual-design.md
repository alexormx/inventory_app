# Página Finanzas: estado de resultados y flujo mensual — diseño

Fecha: 2026-11-07
Estado: aprobado en conversación, pendiente de revisión del documento
Origen: revisión del panel de control del 2026-11-07, "opción A".

## Por qué

El dueño quiere, al cerrar cada mes, responder **"¿gané o perdí dinero y por
qué?"** y ver además el **resultado histórico acumulado**. El panel actual
(`Admin::DashboardController`) no lo responde bien:

- La venta se asigna al mes de `sale_orders.order_date`. Los clientes mandan
  anticipos y la venta se concluye meses después, así que la utilidad cae en
  el mes equivocado y **meses ya revisados cambian después**.
- Un pago reembolsado pasa de `Completed` a `Refunded` y desaparece de los
  cobros de su mes original: otra vez un mes cerrado que cambia, y el
  reembolso nunca aparece como salida de dinero.
- Sólo hay gráficas; no hay una tabla mes por mes ni exportación.

El dueño quiere ver **las dos lecturas**: utilidad (¿el negocio ganó?) y flujo
(¿cuánto dinero entró y salió?), porque paga a proveedores por adelantado y en
un mes de compra grande el flujo sale negativo aunque haya utilidad.

## Contexto del negocio (decidido por el dueño)

- **No cobra IVA** y no lo trata por separado (está evaluando darse de alta
  ante el SAT). No hay desglose de impuestos.
- **Paga a proveedores por adelantado.** La fecha de la orden de compra se
  toma como fecha de pago.
- **No tiene préstamos ni tarjetas** del negocio.
- **No lleva registro de gastos operativos** hoy; eso es un proyecto aparte
  (opción B), fuera de este alcance.
- **Una venta se concluye cuando el cliente termina de pagar.** Ni la
  confirmación manual ni la entrega cuentan.

## Objetivos

1. Página nueva **Finanzas**, sólo para administradores, con enlace en el menú
   lateral de admin. El panel actual no cambia.
2. Tabla mensual tipo hoja de cálculo (el boceto "B" elegido): meses como
   columnas, conceptos como filas.
3. Un mes pasado no cambia por la operación normal posterior (pagos nuevos,
   reembolsos, cambios de estado automáticos). **Sí se recalcula** cuando el
   dueño corrige datos de ese mes: borrar o editar un pago, cancelar o marcar
   como devuelta una venta ya concluida. El dueño eligió recalcular en vez de
   congelar meses cerrados; un "Cerrar mes" con ajustes queda para después.
4. Acumulado histórico de utilidad y de flujo desde la primera operación.
5. Descarga CSV de exactamente lo que se ve, que abra bien en Excel.

## No-objetivos

- Gastos operativos, utilidad neta, IVA, cuentas por pagar, caja y bancos.
- Ver las órdenes detrás de una cifra (drill-down).
- Gráficas nuevas.
- Cambiar cómo calcula el panel actual. Las cifras del panel y de Finanzas
  **van a diferir** porque usan fechas distintas; eso es esperado (ver
  "Decisiones del constructor").

## Anti-objetivos (sería un fracaso aunque funcione)

- Que un mes pasado cambie por la operación normal (un pago nuevo, un
  reembolso, un cambio de estado automático) sin que el dueño haya corregido
  un dato de ese mes.
- Que la página cargue colecciones grandes en memoria: producción es un dyno
  Basic de 512 MB. Todo se agrega en SQL.
- Que un anticipo cuente como ganancia antes de que la venta se concluya.

## La página

### Navegación

- Ruta bajo `/admin`, por ejemplo `admin/finances`, con formatos `html` y `csv`.
- **Vista por defecto: año en curso**, una columna por mes (Ene a Dic) más
  "Total año". El mes en curso lleva la marca "en curso". Los meses futuros
  quedan vacíos.
- **◀ ▶** cambian de año. No se puede ir antes del año de la primera
  operación ni después del año en curso.
- **"Todo el histórico"**: una columna por año, desde el año de la primera
  operación hasta el actual, más una columna "Total".
- En celular la tabla se desliza de lado con la primera columna fija.

### Filas

**Utilidad**

| Fila | Definición |
|---|---|
| Ventas concluidas | Ingreso de las órdenes cuya *fecha de conclusión* cae en el mes: suma de `SaleOrderItem::LINE_REVENUE_SQL` de sus líneas. Mostrar también el número de órdenes. |
| − Descuentos | `sale_orders.discount` de esas mismas órdenes. |
| − Reembolsos | Monto de pagos reembolsados cuya *fecha de reembolso* cae en el mes, de órdenes ya concluidas a esa fecha. |
| − Costo de lo vendido | `SaleOrderItem::LINE_COGS_SQL` de las líneas de las órdenes concluidas en el mes. |
| **Utilidad del mes** | Ventas − descuentos − reembolsos − costo. Con flecha y cambio contra el mes anterior. |
| Margen | Utilidad ÷ (ventas − descuentos). Vacío si el denominador es 0. |
| Utilidad acumulada histórica | Suma de la utilidad de todos los meses desde la primera operación hasta este. |

**Flujo**

| Fila | Definición |
|---|---|
| Cobros (incl. anticipos) | Pagos recibidos con `paid_at` en el mes. "Recibido" = estado `Completed` **o** `Refunded`: un pago reembolsado sí entró en su mes. |
| − Compras y altas manuales | Órdenes de compra no canceladas por `order_date`, con monto `COALESCE(NULLIF(total_cost_mxn, 0), total_order_cost)` **por fila**, más inventario dado de alta sin orden de compra (`purchase_order_id IS NULL AND purchase_order_item_id IS NULL`, `purchase_cost > 0`) por `created_at`. |
| − Reembolsos | Pagos reembolsados por *fecha de reembolso*, sin importar si la venta estaba concluida. |
| **Flujo del mes** | Cobros − compras − reembolsos. Con flecha y cambio contra el mes anterior. |
| Flujo acumulado histórico | Suma del flujo de todos los meses hasta este. |

**Saldos al cierre**

| Fila | Definición |
|---|---|
| Anticipos por entregar | Al último día del mes: dinero recibido (y no reembolsado a esa fecha) de órdenes **no concluidas** a esa fecha y no `Returned`. Incluye órdenes canceladas con pago sin reembolsar, porque es dinero que el negocio tiene y no ha ganado. |
| Inventario a costo | Reconstruido al último día del mes (ver abajo). |

En la vista "Todo el histórico", las filas de flujo y utilidad suman los meses
del año. Los saldos y acumulados toman el valor al cierre del año.

### CSV

Las mismas filas y columnas que la vista actual (año o histórico), con números
sin formato de moneda, punto decimal, UTF-8 con BOM para que Excel respete los
acentos. Nombre: `finanzas-<año|historico>-<fecha>.csv`. Seguir el patrón de
`send_data` de `Admin::ReportsController`.

## Reglas de cálculo

### Fecha de conclusión de una venta

Para cada orden de venta:

1. Ordenar sus pagos recibidos (`Completed` o `Refunded`) por `paid_at` y
   después por `id`.
2. La **fecha de conclusión** es el `paid_at` del pago con el que la suma
   acumulada alcanza o supera `total_order_value`. Se cuentan los
   reembolsados para que un reembolso posterior no "des-concluya" una venta ni
   la saque de su mes.
3. Una orden que alcanzó su total queda reconocida **sin importar su estado
   actual**, salvo `Canceled` o `Returned`. Esto incluye `Pending`, porque un
   reembolso dispara `SaleOrder#update_status_if_fully_paid!` y regresa a
   `Pending` una orden que ya no está totalmente pagada. Sin esta regla, un
   reembolso sacaría la venta de su mes. Cancelar o devolver una venta
   concluida es una corrección del dueño y sí la saca de su mes (objetivo 3).
4. **Respaldo para datos antiguos** *(decisión del constructor)*: sólo una
   orden activa **sin ningún pago recibido** que no sea a crédito
   (`SaleOrder#credit_allowed?`: `users.credit_enabled` o
   `sale_orders.credit_override`) se reconoce en su `order_date`. Toda orden
   con algún pago, aunque sea parcial, espera a liquidarse, para que el último
   pago no la mueva de mes. Una orden a crédito sin liquidar no es venta
   todavía: es cuenta por cobrar. Que el indicador de crédito se lea con su
   valor actual es una imprecisión aceptada.

Se calcula en SQL con funciones de ventana (`SUM(...) OVER (PARTITION BY
sale_order_id ORDER BY paid_at, id)`). Producción, desarrollo y CI usan
PostgreSQL; no hace falta la rama SQLite que tiene el panel.

### Fecha de reembolso

Hoy no existe. Se agrega `payments.refunded_at` de tipo **`date`**, igual que
`paid_at` *(decisión del constructor)*:

- Se fija con `Time.zone.today` al pasar un pago a `Refunded`, si está vacío,
  en el mismo estilo que `set_paid_at_if_completed`. Cubre también el cambio
  automático de `MercadoPago::SyncPayment`.
- **Backfill** en la migración: los pagos ya `Refunded` toman `updated_at`
  convertido a la zona horaria de la app (`Time.zone`) antes de tomar la
  fecha. Debe ser una migración de datos segura y reversible; nunca
  destructiva.
- Los límites de mes se calculan siempre en `Time.zone`.

### Reconstrucción del inventario a costo

Sólo existe el valor de hoy, así que se reconstruye por pieza
(`inventories`). Una pieza cuenta en el inventario al cierre del mes M si:

- **Entró** antes o durante M. Si viene de una orden de compra, la fecha de
  entrada es el `order_date` de esa orden, para ser consistente con el flujo,
  que la toma como pagada ese día. Si es alta manual, su `created_at`.
- **No había salido** al cierre de M. Sale cuando ocurre lo primero de esto:
  - la orden de venta a la que está ligada (`sale_order_id`) se concluyó
    (fecha de conclusión de arriba);
  - pasó a `damaged`, `lost`, `scrap` o `marketing` (fecha:
    `status_changed_at`).
- Una pieza ligada a una orden cancelada o no concluida sigue en inventario.
- Valor: `inventories.purchase_cost`.

Casos con historial incompleto *(decisiones del constructor)*:

- Piezas `sold` o `pre_sold` **sin** `sale_order_id` (datos antiguos): salen
  en su `status_changed_at`.
- `status_changed_at` tiene `CURRENT_TIMESTAMP` por defecto, así que en piezas
  antiguas puede marcar la fecha en que se agregó la columna y no la salida
  real. Se acepta como parte de "no cuadra al peso".
- Piezas con estado de inventario `returned` siguen en inventario.
- Piezas con `purchase_order_id` pero sin `purchase_order_item_id` entran en
  el `order_date` de su orden de compra y **no** se cuentan como alta manual
  en el flujo (ya están en el total de la orden). La alta manual queda
  definida como `purchase_order_id IS NULL AND purchase_order_item_id IS NULL`
  y `purchase_cost > 0`. El panel actual sólo filtra por
  `purchase_order_item_id`, así que podría contar dos veces esas piezas; no se
  toca aquí, pero hay que mencionarlo al dueño.

Así, la mercancía entregada a crédito y aún no pagada sigue contando como
inventario a costo hasta que la venta se concluye. Es consistente con la regla
de reconocimiento.

El dueño aceptó que esta cifra **puede no cuadrar al peso** con la realidad:
el costo de lo vendido usa `unit_acquisition_cost` (promedio congelado),
mientras que el inventario usa el costo de cada pieza, y hay ajustes
históricos que no se pueden reconstruir con exactitud.

## Restricciones

- Producción: dyno Basic de 512 MB. Agregar en SQL y traer sólo los totales
  por mes (unas cuantas filas por concepto), nunca órdenes o piezas.
- Sólo administradores (mismo `authorize_admin!` que el panel).
- Ruby 3.2.3 vía RVM (`~/.rvm/bin/rvm 3.2.3 do ...`). El esquema de la base de
  prueba se prepara con `db:test:prepare`, nunca `db:prepare`. Nunca correr
  comandos destructivos contra la base de desarrollo.
- Tras la migración, el deploy es un solo `git push heroku main` (la fase
  `release:` migra).

## Decisiones del constructor (tomadas en el diseño, revisables)

- **Envío cobrado al cliente:** no está en las líneas, así que no entra en
  "Ventas concluidas", igual que en el panel. Sí entra en los cobros, porque
  el cliente lo pagó. El costo real de paquetería tampoco está; ambos llegan
  con la opción B (gastos).
- **Devoluciones (`Returned`):** se excluyen igual que hoy. Limitación
  conocida: si una venta concluida se marca como devuelta, sale de su mes
  original. Un registro de fecha de devolución queda para después.
- **Órdenes de compra canceladas:** se excluyen del flujo. Si alguna se pagó
  por adelantado y el proveedor devolvió el dinero, hoy no hay dónde
  registrarlo.
- **Diferencias con el panel:** se agrega una nota breve en la página
  explicando que Finanzas cuenta la venta al liquidarse y el panel por fecha
  de orden.

## Lo que queda al constructor

- Nombres de clases y servicios. Sugerencia: un servicio
  `Finance::MonthlyStatement` que devuelva una estructura por mes o año,
  usado por la vista HTML y por el CSV.
- Estructura de las consultas SQL y si la fecha de conclusión vive en un CTE o
  una vista.
- Estilo visual: debe seguir el layout `admin` y Bootstrap como el resto del
  panel.
- Pruebas: como mínimo, specs del servicio para la fecha de conclusión
  (anticipo en un mes y liquidación en otro, pagos múltiples, crédito sin
  liquidar, orden antigua sin pagos), reembolsos (no cambian el mes
  original; cuentan en el mes del reembolso), compras con y sin
  `total_cost_mxn`, anticipos por entregar, la reconstrucción de inventario y
  un request spec del HTML, del CSV y del acceso sólo para admin.
