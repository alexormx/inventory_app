# Auditoría del flujo de compra y checkout — 2026-07

Alcance: descubrimiento de producto → carrito → checkout → pago → confirmación, incluyendo inventario, reservas, UX, accesibilidad, seguridad, performance y analytics. Auditoría de solo lectura; no se modificó código. Cada hallazgo distingue **problema confirmado** de **recomendación que requiere decisión de negocio**.

---

## 1. Resumen ejecutivo

La base técnica del checkout es mejor de lo habitual en proyectos de este tamaño: los precios y totales se calculan siempre en servidor, el checkout es transaccional con doble validación de disponibilidad, la idempotencia contra pedidos duplicados está bien diseñada (token de sesión + índice único + `secure_compare`), y la autorización está bien acotada a `current_user` (sin IDOR en pedidos, direcciones ni carrito).

Sin embargo, **no se recomienda aceptar pedidos reales hasta corregir la Fase 1**, por cuatro razones:

1. **Bug de preventas huérfanas**: el checkout crea `PreorderReservation` con `sale_order: nil`, lo que puede generar **pedidos duplicados** cuando llegue stock (el asignador crea un pedido nuevo) y reservas que **nunca se cancelan** aunque el cliente cancele.
2. **Nada expira**: una reserva de un cliente que nunca paga retiene inventario **indefinidamente** (solo existe liberación manual pieza por pieza, 90+ días, vía reporte admin).
3. **El correo de confirmación existe pero nunca se envía**, aunque la página de gracias lo promete dos veces.
4. **Fallas silenciosas en producción**: errores al reservar inventario y al crear el pago se tragan con solo un log, dejando pedidos sin inventario o sin pago (que jamás podrán auto-confirmarse).

Además hay inconsistencias de dinero visibles al cliente (el carrito estima envío $99/gratis ≥$1500 pero el checkout cobra $0; el carrito puede mostrar IVA que el pedido nunca cobra), datos bancarios semilla de ejemplo (`012345678901234567`), y una exposición de privacidad en los códigos de lista WhatsApp (`WA-2026-0001` es enumerable y público).

---

## 2. Diagrama del flujo actual

```
INVITADO                                    AUTENTICADO
   │                                            │
   ▼                                            ▼
home#index ──► /catalog (products#index) ──► products#show
   │            búsqueda pg_trgm, filtros,      (precio/disponibilidad
   │            sort, paginación kaminari        solo con login)
   │                                            │
   │                                            ▼
   │                                     POST /cart_items (button_to + Turbo)
   │                                     session[:cart] = {product_id => {condición => qty}}
   │                                     valida sellable_inventory + MAX 3 (1 coleccionable)
   │                                     toast + badge navbar (turbo_stream)
   │                                            │
   │                                            ▼
   │                                     GET /cart (carts#show)
   │                                     qty +/- (fetch crudo, cart_item_controller.js)
   │                                     mini-cart (Turbo forms)
   │                                            │
   ▼                                            ▼
/whatsapp-list (solo invitados)        authenticate_user! requerido
WhatsappRequest en DB                    GET /checkout/step1 (confirma items + notas)
cookie firmada 60 días                   POST step1 → guarda notas en sesión
"checkout" = redirect a wa.me            GET/POST /checkout/step2 (dirección + método envío)
tracking público /lista/WA-YYYY-####     GET /checkout/step3 (pago + resumen, genera checkout_token)
   │                                     POST /checkout/complete
   │                                       ├─ verifica token (secure_compare)
   │                                       ├─ busca pedido por idempotency_key
   │                                       └─ Checkout::CreateOrder
   │                                            ├─ validación disponibilidad (sin lock)
   │                                            ├─ TRANSACCIÓN: lock productos (FOR UPDATE)
   │                                            │    re-valida disponibilidad
   │                                            │    SaleOrder (Pending, tax 0)
   │                                            │    SaleOrderItems → after_save reserva
   │                                            │    inventario (available/in_transit → reserved)
   │                                            │    PreorderReservation (sale_order: nil ⚠)
   │                                            │    OrderShippingAddress snapshot
   │                                            │    recalculate_totals!
   │                                            ├─ FUERA de transacción: Payment.create!(Pending) ⚠
   │                                            └─ limpia sesión → redirect
   │                                            ▼
   │                                     GET /checkout/thank_you?order_id=
   │                                     (promete email que nunca se envía ⚠)
   │                                            ▼
   │                                     /orders (index/show/summary)

ADMIN: pagos manuales (admin/payments), estados de pedido, liberación manual
de reservas viejas (reporte, 90 días), reevaluación manual de in_transit→pre_reserved.
NO hay jobs programados para reservas ni auto-asignación (recurring.yml).
```

**Archivos involucrados**

- Rutas: `config/routes.rb:349-397` (catálogo, cart_items, cart, whatsapp-list, checkout, orders, páginas estáticas).
- Controladores: `products_controller.rb`, `home_controller.rb`, `cart_items_controller.rb`, `carts_controller.rb`, `checkouts_controller.rb`, `orders_controller.rb`, `shipping_addresses_controller.rb`, `whatsapp_lists_controller.rb`.
- Modelos: `cart.rb` (PORO sobre sesión), `cart_item.rb` (**muerto**), `product.rb`, `inventory.rb`, `sale_order.rb`, `sale_order_item.rb`, `payment.rb`, `payment_method.rb`, `shipping_method.rb`, `preorder_reservation.rb`, `order_shipping_address.rb`, `whatsapp_request.rb`, `site_setting.rb`.
- Servicios: `Checkout::CreateOrder`, `InventoryServices::AvailabilitySplitter`, `Shipping::Calculator/*`, `SaleOrders::AutoAssignInventoryService`, `SaleOrders::CancelOldReservations` (**muerto**), `Preorders::PreorderAllocator`, `Inventories::ReevaluateStatusesService`, concern `InventorySyncable`.
- Vistas: `app/views/{home,products,carts,cart_items,checkouts,orders,shipping_addresses,whatsapp_lists,pages,layouts,customers/partials}`.
- JS: esbuild bundle `application.js`; Stimulus registry `controllers/customer.js`; `cart_item_controller.js`, `catalog_filters_controller.js`, `navbar_toggle.js`, `cart_preview.js`, `bootstrap_polyfills.js`; turbo streams en `app/views/cart_items/*.turbo_stream.erb`. `config/importmap.rb` está **obsoleto/sin uso**.

---

## 3. Lo que ya está bien implementado

- **Precios/totales 100% servidor**: el navegador nunca envía precios; `Cart#build_items` lee `selling_price` de la BD; `SaleOrder#recalculate_totals!` recalcula desde líneas. Sin vector de tampering encontrado.
- **Idempotencia de checkout ejemplar**: token en sesión + `secure_compare` + índice único `(user_id, idempotency_key)` + pre-chequeo + rescue de carrera. Bien probado (`spec/requests/checkouts_idempotency_spec.rb`).
- **Transacción con doble validación de stock** y lock pesimista de productos en `Checkout::CreateOrder`; rollback limpio con mensajes en español.
- **Autorización correcta**: todo lo de cliente tras `authenticate_user!`, lookups acotados a `current_user`, `params.expect` en direcciones, CSRF por defecto (Rails 8).
- **Add-to-cart Turbo sólido**: toast rico con thumbnail y CTA, badge del navbar y mini-cart actualizados por turbo_stream, botón deshabilitado durante el request.
- **Carrito anónimo → autenticado sin fricción**: la sesión sobrevive al login de Devise; no hace falta merge.
- **Búsqueda de catálogo buena**: pg_trgm + ILIKE sanitizado + orden por relevancia + match exacto por código WhatsApp; filtros y facets parametrizados; paginación; precargas batch (imágenes, on-hand, reviews, ETAs).
- **SEO**: slugs FriendlyId, landings marca/categoría/serie, canonical, JSON-LD, sitemap, robots, 301 de rutas legacy.
- **Accesibilidad base**: `lang="es"`, captions/scope en tablas, `aria-live` en totales, labels en formularios, ratings con `aria-label`, progress bar con `aria-current`.
- **Estados vacíos buenos** en catálogo (3 variantes según contexto) y lista WhatsApp.
- **Sin superficie PCI**: no se captura ni guarda ningún dato de tarjeta del cliente.
- **Sync estado↔inventario completa**: reserved↔sold en transiciones, liberación al cancelar, guards contra borrar líneas vendidas.

---

## 4. Problemas críticos funcionales o de seguridad

### C1. Preventas huérfanas → riesgo de pedidos duplicados y reservas incancelables
- **Comportamiento actual**: checkout crea `PreorderReservation` con `sale_order: nil` (`app/services/checkout/create_order.rb:148-156`). Al llegar stock, `Preorders::PreorderAllocator` ve `sale_order` nil y **crea un SaleOrder nuevo** (`app/services/preorders/preorder_allocator.rb:53-61`), mientras la línea original mantiene `preorder_quantity` sin decrementar.
- **Problema**: duplicación de pedidos/doble surtido; la cancelación del pedido (`sale_order_item.rb:145`) nunca cancela la reserva huérfana (filtra por `sale_order_id`).
- **Impacto cliente**: le pueden generar un segundo pedido/cargo por la misma preventa; cancelar no cancela.
- **Impacto negocio**: sobreventa, disputas, trabajo manual de conciliación.
- **Solución**: crear la `PreorderReservation` con el `sale_order`/`sale_order_item` reales y ajustar el allocator para surtir la línea existente (decrementar `preorder_quantity`) en vez de crear pedidos.
- **Prioridad**: Critical. **Complejidad**: Media. **Cambios DB**: no (columnas existen).
- **Tests**: spec de servicio checkout-con-preventa → allocator surte la misma línea; cancelación libera la reserva; no se crea SaleOrder adicional.

### C2. El rescue de doble-submit concurrente nunca matchea (mensaje estilo MySQL)
- **Comportamiento actual**: `checkouts_controller.rb:157` — `raise e unless e.message.include?('sale_orders.index_sale_orders_on_user_and_idempotency')`. PostgreSQL (producción) y SQLite no incluyen ese prefijo en el mensaje.
- **Problema**: la ruta de recuperación de carrera (líneas 159-167) es código muerto; doble-submit verdaderamente concurrente → 500.
- **Impacto cliente**: error 500 en lugar de redirect amable a su pedido (que sí se creó). **Impacto negocio**: tickets de soporte, desconfianza en el momento más sensible.
- **Solución**: matchear por `e.cause` (PG::UniqueViolation / SQLite3 constraint) o por nombre de índice sin prefijo de tabla; mejor: `SaleOrder.upsert`/re-query por `idempotency_key` en el rescue.
- **Prioridad**: Critical. **Complejidad**: Baja. **DB**: no. **Tests**: request spec que fuerce `RecordNotUnique` y verifique redirect al pedido existente.

### C3. El correo de confirmación existe pero nunca se envía
- **Comportamiento actual**: `OrderConfirmationMailer` con templates HTML/texto y spec completo, **sin ninguna llamada** en producción. `thank_you.html.erb:15,158` promete correos de confirmación y de envío que jamás llegan. Tampoco hay correo al cambiar a Confirmed/Enviado.
- **Impacto cliente**: no recibe comprobante ni instrucciones de pago por escrito; si pierde la página de gracias, no tiene dónde depositar. **Impacto negocio**: pagos no realizados, abandono post-compra, promesa incumplida.
- **Solución**: enviar `OrderConfirmationMailer` tras commit en `Checkout::CreateOrder` (o `after_commit` en SaleOrder) y correos de cambio de estado clave (confirmado, enviado con guía).
- **Prioridad**: Critical. **Complejidad**: Baja. **DB**: no. **Tests**: spec que complete un checkout y assertee el mail enqueued; specs de correo de estado.

### C4. Reservas sin expiración: inventario retenido indefinidamente
- **Comportamiento actual**: `config/recurring.yml` no tiene ninguna tarea de limpieza; `SaleOrders::CancelOldReservations` existe pero **nada lo invoca**; `InventoryAutoAssignmentJob` tampoco está programado. Liberación solo manual, pieza por pieza, con default de 90 días (`admin/reports_controller.rb:15-61`).
- **Impacto cliente**: productos "sin stock" que en realidad están podridos en carritos abandonados. **Impacto negocio**: ventas perdidas, stock fantasma, cobros de preventas sin orden.
- **Solución**: programar en `recurring.yml` (Solid Queue) una pasada periódica: pedidos Pending sin pago > N días → cancelar + liberar (ya existe la lógica de release); y programar el auto-assignment job. Definir N con negocio (sugerido: 3-7 días para transferencia).
- **Prioridad**: Critical. **Complejidad**: Baja-Media. **DB**: no (basta `status_changed_at`/`created_at`). **Tests**: spec del job con pedidos viejos/nuevos; spec de release de inventario.

### C5. Fallas de reserva tragadas en producción (silent under-reservation)
- **Comportamiento actual**: `InventorySyncable#sync_inventory_records` rescata todo y solo loggea en producción (`app/models/concerns/inventory_syncable.rb:21-26`); la nota 🛑 también queda dentro del bloque rescatado.
- **Problema**: un pedido puede quedar sin inventario reservado sin que nadie se entere; como el job de auto-asignación no corre (C4), nadie lo repara.
- **Solución**: no tragar el error dentro de la transacción (dejar que haga rollback) o, mínimo, nota en el pedido + alerta (mail admin / log estructurado) y job de reconciliación programado.
- **Prioridad**: Critical. **Complejidad**: Baja. **DB**: no. **Tests**: spec que fuerce fallo de reserva y verifique rollback/notificación.

### C6. `sold_price = 0.0` al reservar en checkout
- **Comportamiento actual**: `inventory_syncable.rb:105` usa `unit_final_price.to_f` cuando aún es nil → 0.0; el backfill posterior (`create_order.rb:196-203`) solo corrige `sale_order_item_id`.
- **Impacto negocio**: reportes de margen/utilidad corruptos para todo lo vendido por storefront.
- **Solución**: calcular precio de línea antes de reservar (pasar el precio al sync) o corregir `sold_price` en el backfill.
- **Prioridad**: Critical (datos financieros). **Complejidad**: Baja. **DB**: no. **Tests**: spec que verifique `sold_price` = precio real tras checkout.

### C7. Creación de Payment fuera de la transacción y falla tragada
- **Comportamiento actual**: `create_order.rb:183-193` — `Payment.create!` post-commit con rescue que solo loggea.
- **Problema**: pedido sin Payment jamás auto-confirma (`update_status_if_fully_paid!` depende de callbacks de Payment). Cliente ve éxito.
- **Solución**: mover dentro de la transacción o usar `EnsurePaymentService` en un job `after_commit` con reintento.
- **Prioridad**: Critical. **Complejidad**: Baja. **DB**: no. **Tests**: spec de fallo de Payment → pedido sigue consistente/reparable.

### C8. Piezas en tránsito se marcan `reserved` (almacén) en vez de `pre_reserved`
- **Comportamiento actual**: la reserva toma de `Inventory.assignable` (available + in_transit) y marca todo `reserved` (`inventory_syncable.rb:99-108`); la corrección a `pre_reserved` solo ocurre con `ReevaluateStatusesService`, que se dispara **manual** desde Settings.
- **Impacto negocio**: reportes de "disponible para surtir" inflados; riesgo de prometer fechas imposibles.
- **Solución**: preservar el status correcto al reservar (in_transit → pre_reserved) o programar la reevaluación.
- **Prioridad**: High-Critical. **Complejidad**: Baja. **DB**: no. **Tests**: spec de checkout de item en tránsito → pieza queda `pre_reserved`.

### C9. Bug de capitalización: página de gracias siempre muestra "Pendiente"
- **Comportamiento actual**: `thank_you.html.erb:63-64,149` compara `payment.status == 'completed'` pero el enum guarda `'Completed'`.
- **Impacto cliente**: aunque admin marque el pago completado, el cliente siempre ve "Pendiente" y los datos bancarios. Confusión y mensajes de soporte.
- **Solución**: comparar contra `Payment::STATUSES` / helper. **Prioridad**: High (visible y trivial). **Complejidad**: Muy baja. **DB**: no. **Tests**: view/request spec de thank_you con pago Completed.

### C10. Códigos de lista WhatsApp enumerables y públicos
- **Comportamiento actual**: tracking en `/lista/WA-YYYY-####` secuencial, sin autenticación (`whatsapp_request.rb:77-86`), mostrando nombre, teléfono e items del cliente.
- **Problema/riesgo**: cualquiera puede iterar códigos y leer PII de clientes. Incumple el principio del aviso de privacidad.
- **Solución**: token opaco (SecureRandom) en la URL de tracking, o requerir verificación (teléfono + código corto).
- **Prioridad**: Critical (privacidad). **Complejidad**: Baja. **DB**: sí (columna token + índice) o usar signed_id. **Tests**: request spec de acceso con/sin token válido.

### C11. Checkout sin aceptación de Términos/Aviso de Privacidad
- **Comportamiento actual**: no existe checkbox de aceptación en ningún paso (grep confirmado); solo el de tiempos extendidos cuando hay preventa.
- **Impacto negocio/legal**: debilita la exigibilidad de políticas de devolución/cancelación; inconsistente con pedir depósitos bancarios.
- **Solución**: checkbox requerido en step3 con links a `/terminos-y-condiciones` y `/aviso-de-privacidad`, guardando `terms_accepted_at` en el pedido.
- **Prioridad**: High (legal). **Complejidad**: Baja. **DB**: sí (1 columna, opcional pero recomendable). **Tests**: request spec step3 sin checkbox → 422; con checkbox → pedido con timestamp.

### C12. Datos bancarios semilla de ejemplo
- **Comportamiento actual**: `db/seeds.rb:32-46` — CLABE `012345678901234567` y tarjeta OXXO placeholder.
- **Impacto negocio**: si producción usa seeds, los clientes depositan a una cuenta falsa.
- **Solución**: verificar/configurar los `PaymentMethod` reales vía admin antes de abrir; quitar datos placeholder de seeds o marcarlos inactivos por defecto.
- **Prioridad**: Critical (operativa). **Complejidad**: Muy baja. **DB**: no (datos). **Tests**: n/a — checklist de despliegue.

### C13. El lock de productos no cubre las otras rutas de reserva
- **Comportamiento actual**: checkout bloquea productos, pero `AutoAssignInventoryService`, `PreorderAllocator` y ediciones admin de líneas no toman locks ni re-verifican la pieza antes de `update!(status: :reserved)` (`inventory_syncable.rb:100-107`, `auto_assign_inventory_service.rb:114-143`).
- **Problema**: carrera admin/auto-assign vs checkout puede sobreescribir `sale_order_id` de la última pieza (doble reserva).
- **Solución**: guard atómico por pieza: `Inventory.where(id:, sale_order_id: nil, status: [...]).update_all(...)` verificando rows affected, o lock de la pieza.
- **Prioridad**: High. **Complejidad**: Media. **DB**: no. **Tests**: spec de concurrencia (dos procesos reservando la última pieza).

---

## 5. Mejoras de UX y diseño profesional

Cada item: comportamiento actual → archivo → impacto → solución → prioridad/complejidad/DB/tests.

1. **Envío e impuestos inconsistentes entre carrito y checkout** — Carrito estima envío $99 (gratis ≥$1500) y puede mostrar IVA (`cart.rb:4-5,100-133`); checkout cobra lo del `Shipping::Calculator` (estándar = $0) y siempre tax 0 (`create_order.rb:108-109`). El "total" del carrito no es el total real. → Unificar: usar la misma fuente (ShippingMethod/SiteSetting) en ambos o etiquetar claramente "por calcular". **High / Baja / no / specs de Cart vs CreateOrder coherentes.**
2. **Terminología subtotal/total invertida** — `carts/show.html.erb:32` ("Total" = subtotal) vs `:56` ("Subtotal" = subtotal+tax). Confuso. **Media / Muy baja / no / view spec.**
3. **Precio visible a invitados en catálogo pero oculto en la página de producto** — `_summary_panel.html.erb:113-125` dice "Inicia sesión para ver el precio" de un precio ya visto en la card. **Decisión de negocio** (¿precios públicos sí/no?) + hacerlo consistente. **High / Baja / no / view specs.**
4. **Sin checkbox de Términos/Privacidad** — ver C11.
5. **Estados de pedido en inglés al cliente** — `orders/index.html.erb:20`, `orders/show.html.erb:5` muestran "Pending/In Transit" crudos. → helper de traducción. **High / Muy baja / no / helper spec.**
6. **ETA engañoso "~90 días" hardcodeado** — `products_helper.rb:95,121` vs setting de 60 días. **High / Muy baja / no / helper spec.**
7. **thank_you siempre "Pendiente"** — ver C9.
8. **orders#show sin datos de pago ni instrucciones** — cliente que pierde thank_you no sabe dónde depositar; tampoco hay guía/rastreo aunque thank_you lo promete (`thank_you.html.erb:161`). → bloque de pago (estado, CLABE, monto pendiente) + envío en orders#show. **High / Baja / no / request spec.**
9. **Footer sin contacto ni políticas** — `_footer.html.erb`: sin dirección, teléfono, email, envíos/devoluciones; términos referencian una "sección de Ayuda" inexistente (`pages/terms.html.erb:33`). Para una tienda que pide depósitos, es crítico de confianza. **High / Baja / no / —.**
10. **Layout de Devise distinto y sin footer** — `application.html.erb:29` con clases Tailwind en proyecto Bootstrap, sin footer/cookies/WhatsApp. Login/registro se ven de otra app. **Media / Baja / no / —.**
11. **Imágenes sin `alt` en checkout/thank_you** — `step1.html.erb:41`, `step3.html.erb:129`, `_cart_summary.html.erb:26`, `thank_you.html.erb:99`; además `role="text"` inválido en `_product_grid.html.erb:107`. **Media / Muy baja / no / lint de vistas.**
12. **Fila del carrito sobrecargada de badges** — hasta 4-5 indicadores de disponibilidad por línea con info duplicada (`_cart_item.html.erb:26-84`). Consolidar en un solo indicador + ETA. **Media / Baja / no / —.**
13. **Productos listados dos veces en step3** (columna principal + sidebar). **Baja / Muy baja / no / —.**
14. **"Backorder" en inglés** en relacionados (`show.html.erb:215`) vs "Sobre pedido" en el resto; badge "Default" vs "Principal" en direcciones; aria-labels en inglés ("Toggle navigation", "Close"); emojis en H1 vs Font Awesome en el resto. **Baja / Muy baja / no / —.**
15. **Errores de checkout solo como flash, sin resaltado inline**; y `result.errors.join(', ')` crudo puede filtrar mensajes de modelo en inglés (`checkouts_controller.rb:152`). **Media / Baja / no / request spec.**
16. **Número de pedido = ID crudo** — sin folio formateado (ej. `PED-2026-000123`). **Baja / Baja / no (formatear en display) / —.**
17. **Promesas sin cumplir en UI**: "Rastrea tu pedido… con número de guía" sin guía visible; "Métodos de Pago Seguro" genérico sin métodos reales. **Media / Baja / no / —.**
18. **Sin confirmación de recepción de pago para el cliente**: tras enviar comprobante por WhatsApp no hay estado "pago en revisión". **Decisión de negocio / Media / quizá (status) / —.**
19. **Home duplica propuesta de valor** (trust badges + value cards). **Baja / Muy baja / no / —.**
20. **"Clientes Felices"** mayúscula media; "Cantid."/"Costo unit" en `orders/summary.html.erb` (terminología interna frente al cliente). **Baja / Muy baja / no / —.**

---

## 6. Funcionalidad e-commerce faltante

1. **Guest checkout** — hoy obliga registro (guests se derivan a WhatsApp). **Decisión de negocio**: si se permite, el Checkout::CreateOrder necesita crear/invitar usuario o pedidos sin cuenta. Complejidad Media-Alta, DB posiblemente.
2. **Pasarela de pago con tarjeta** — `PaymentMethod` "Tarjeta" existe inactiva ("próximamente"); estructura de `payments` lista. Requiere decisión de gateway (MercadoPago/Conekta/Stripe), webhooks idempotentes, y nunca guardar PAN. Alta.
3. **Cupones/descuentos en checkout** — columnas `discount`/`unit_discount` existen (admin-only); no hay flujo de cupón. Media (validar siempre servidor-side).
4. **"Avísame cuando vuelva"** para sin stock. Media (DB nueva tabla o reutilizar preorders).
5. **Correos de ciclo de vida del pedido** (confirmado/enviado con guía/entregado) — ver C3. Baja una vez C3.
6. **Recuperación de carrito abandonado** — hoy el carrito es de sesión (no recuperable por email); requeriría carrito persistido para usuarios logueados. **Decisión de negocio + privacidad (consentimiento)**. Alta (DB).
7. **Número de guía y rastreo en orders#show** — el dato existe parcialmente en summary (carrier). Baja-Media.
8. **Fecha estimada de entrega por método de envío** — los métodos no exponen ETA al cliente. Baja.
9. **Página de envíos/devoluciones pública** (políticas claras) — solo existe en términos parcialmente. Muy baja (contenido).
10. **Pago parcial/anticipo en checkout** — soportado estructuralmente (varios Payments), no expuesto. Decisión de negocio.
11. **Historial con estado de pago** en orders#index/show. Baja.

---

## 7. Problemas específicos de mobile

1. **Carrito y step1 usan tablas con scroll horizontal** (`.table-responsive`, anchos fijos en px, `step1.html.erb:26-28`); input de cantidad `width:50px` fijo. → layout de cards apiladas en <576px. **High / Media / no / system spec mobile.**
2. **Touch targets pequeños**: steppers del mini-cart ~24px (`_cart_preview_body.html.erb:54-57`), botón copiar CLABE `py-0 px-1`. **Media / Muy baja / no / —.**
3. **Mini-cart preview es hover/focus**: sin tap-to-toggle en touch (`cart_preview.js`); usable pero el preview es inaccesible en móvil. **Baja / Baja / no / —.**
4. **`orders/summary` con `min-width:320px`** puede desbordar pantallas <360px. **Baja / Muy baja / no / —.**
5. **Quantity update por fetch sin serialización** (clics rápidos compiten) — más probable en móvil. Ver TD2.
6. Aspectos buenos: grid 2 col, buscador sticky, filtros en offcanvas, paginador compacto, summary sticky se vuelve estático correctamente.

---

## 8. Deuda técnica

1. **TD1 — Controllers Stimulus de checkout no registrados en el bundle cliente**: `selectable-cards` y `checkout-shipping` solo están en `controllers/index.js` (admin), no en `customer.js`. El UX sin recarga de step2/step3 es código muerto en producción. **Alta / Muy baja / no / system spec.**
2. **TD2 — `cart_item_controller.js` (fetch crudo)**: sin manejo de 422/red → pinta `undefined` en cantidad y totales; sin debounce ni serialización; duplica ~50 líneas lo que ya hace `update_row.turbo_stream.erb`. → reemplazar por formularios Turbo como el mini-cart. **Alta / Baja-Media / no / request + system specs de qty.**
3. **TD3 — Errores del mini-cart no se muestran**: `update.turbo_stream.erb:15-18` solo renderiza `:notice`, los `:alert` de stock se pierden. **Alta / Muy baja / no / request spec.**
4. **TD4 — Branching por `request.referer`** en `CartItemsController` (líneas 62,123,165): con Referer bloqueado se renderiza el template equivocado. → usar parámetro explícito (`context=cart`) o un solo template turbo_stream idempotente. **Media / Baja / no / request spec sin referer.**
5. **TD5 — `CartItem` AR + tabla `cart_items` muertos**; `config/importmap.rb` obsoleto; `app/views/products/index.html.erb.backup`; partial `_value_card` sin uso; `data-controller="product-conditions"` inexistente; `<script>` inline redundante en step3 (rompería CSP estricta); `onclick` inline en `posts/show.html.erb:107`. **Baja / Muy baja / DB: drop table opcional / —.**
6. **TD6 — SiteSetting N+1**: `SiteSetting.get` sin cache → hasta ~120 queries extra por página de catálogo (`products_helper.rb:70-71`, `product.rb:682`). → cache en RequestStore/Rails.cache con invalidación al guardar. **Media / Baja / no / spec de cache.**
7. **TD7 — Home featured con N+1 y filtrado en vista** (`home_controller.rb:9`, `index.html.erb:176`): sin `with_attached_product_images`, `current_on_hand` por producto, y puede mostrar <8. **Media / Baja / no / —.**
8. **TD8 — Doble definición de "disponible"**: grid usa `current_on_hand` (incluye piezas sin ubicación y asignadas), PDP/carrito usan `sellable_inventory` (estricto) → las cards pueden sobreestimar stock (`products_controller.rb:146` vs `product.rb:511-514,628-634`). Unificar. **Alta / Baja / no / model spec.**
9. **TD9 — Recálculos redundantes**: `recalculate_parent_order_totals` after_commit por línea (N+1 recalcula N veces); un `UpdateStatsService` por pieza reservada; `AutoAssignInventoryService#sale_order_items_needing_inventory` N+1 que crece con el backlog; `@top_categories` en cada carga de catálogo aunque solo se usa en empty state. **Media / Baja-Media / no / specs de performance opcionales.**
10. **TD10 — Raza lógica en límites de carrito** (check-then-increment en sesión) — teórica con cookie store; menor. **Baja.**
11. **TD11 — FriendlyId sin `:history`**: si un slug se regenera, URLs viejas redirigen 302 al catálogo. **Baja / Baja / no / —.**
12. **TD12 — Sonda de existencia por ID numérico**: `products#show` acepta ID numérico y el mensaje de redirect distingue borrador/inactivo. **Baja / Muy baja / no / request spec.**
13. **TD13 — `test/` minitest obsoleto** (fallaría; p.ej. `order_confirmation_mailer_test.rb`) junto a RSpec vivo. Decidir: borrar o mantener. **Baja.**
14. **TD14 — `bootstrap_polyfills.js`** (~270 líneas reimplementando Bootstrap JS): deliberado, funciona, pero es superficie de mantenimiento. **Opcional.**

---

## 9. Flujo objetivo recomendado

```
Descubrimiento (público, precios según decisión de negocio consistente en card y PDP)
   → PDP con disponibilidad real unificada (stock / tránsito con ETA / preventa / sobre pedido / agotado + "avísame")
   → Agregar al carrito (Turbo, validación servidor, toast, badge)
   → Carrito: qty vía Turbo con errores inline, un solo indicador de disponibilidad por línea,
     subtotal/envío/impuestos/total calculados con las MISMAS reglas que checkout,
     revalidación de disponibilidad al entrar a checkout (items que cambiaron → aviso, no sorpresa)
   → Checkout 3 pasos (o 1 página con secciones) con progress bar:
     1) datos/envío (dirección guardada o nueva; guest checkout si negocio lo aprueba)
     2) método de envío con costo real + ETA
     3) pago (instrucciones bancarias reales o tarjeta) + resumen + aceptación Términos/Privacidad
   → POST complete: idempotente (ya bien), transacción con reserva atómica por pieza,
     pre_reserved correcto para tránsito, preorder ligada al pedido, Payment dentro de la transacción
   → Thank you: folio formateado, estado de pago correcto, instrucciones claras, próximos pasos reales
   → Email de confirmación + emails de estado (confirmado, enviado con guía)
   → Job programado: expirar reservas de pedidos sin pago a N días; auto-asignación; reconciliación
   → orders#show como "centro del pedido": pago, instrucciones, guía, estados en español
```

---

## 10. Roadmap priorizado

### Fase 1 — Correcciones críticas antes de aceptar pedidos reales
| # | Acción | Esfuerzo | DB |
|---|--------|----------|----|
| 1 | C1: ligar PreorderReservation al pedido y corregir allocator (anti duplicados) | M | no |
| 2 | C4: programar expiración de reservas + auto-assignment job en recurring.yml (definir TTL con negocio) | B-M | no |
| 3 | C3: enviar email de confirmación de pedido | B | no |
| 4 | C12: configurar PaymentMethod/ShippingMethod reales; quitar placeholders | B | datos |
| 5 | C5+C7: dejar de tragar errores de reserva y mover Payment a la transacción | B | no |
| 6 | C2: arreglar matcher de RecordNotUnique (PG/SQLite) | B | no |
| 7 | C6: sold_price correcto al reservar | B | no |
| 8 | C10: token opaco en tracking de listas WhatsApp | B | sí |
| 9 | C8: in_transit → pre_reserved al reservar | B | no |
| 10 | C9: bug 'completed' vs 'Completed' en thank_you | MB | no |
| 11 | C11: checkbox Términos/Privacidad en step3 | B | sí (1 col) |
| 12 | C13: reserva atómica por pieza (guard anti doble-reserva) | M | no |

### Fase 2 — Checkout profesional mínimo
| # | Acción | Esfuerzo | DB |
|---|--------|----------|----|
| 1 | Unificar envío/impuestos carrito↔checkout (misma fuente de verdad) | B-M | no |
| 2 | TD2+TD3+TD4: qty del carrito vía Turbo con errores inline; matar fetch crudo y branching por referer | B-M | no |
| 3 | TD1: registrar controllers de checkout en bundle cliente | MB | no |
| 4 | orders#show: estado de pago, instrucciones bancarias, monto pendiente | B | no |
| 5 | Estados de pedido en español; fix "~90 días"; terminología subtotal/total | MB | no |
| 6 | Footer con contacto + páginas de envíos y devoluciones; arreglar referencia muerta a "Ayuda" | B | no |
| 7 | TD8: unificar definición de disponibilidad (cards vs PDP vs carrito) | B | no |
| 8 | Decidir y hacer consistente visibilidad de precios a invitados | B | no |
| 9 | Carrito en mobile: layout de cards en vez de tabla; touch targets ≥44px | M | no |
| 10 | Layout Devise alineado al storefront (footer, estilos) | B | no |

### Fase 3 — Conversión y usabilidad
| # | Acción | Esfuerzo | DB |
|---|--------|----------|----|
| 1 | Guest checkout (si negocio lo aprueba) | M-A | quizá |
| 2 | Emails de ciclo de vida (confirmado, enviado con guía, entregado) | B-M | no |
| 3 | "Avísame cuando vuelva" para agotados | M | sí |
| 4 | Folio de pedido formateado + guía/rastreo visible | B | no |
| 5 | Consolidar badges de disponibilidad; limpiar step3 duplicado | B | no |
| 6 | Accesibilidad: alts faltantes, role="text", cookie banner, foco visible | B | no |
| 7 | Analytics de funnel (ver §11) | B-M | no |
| 8 | Revalidación de carrito al entrar a checkout con aviso de cambios | M | no |
| 9 | Performance: cache SiteSetting, fix N+1 home/recálculos | B-M | no |

### Fase 4 — Avanzado / opcional
| # | Acción | Esfuerzo | DB |
|---|--------|----------|----|
| 1 | Pasarela de tarjeta (MercadoPago/Conekta/Stripe) con webhooks idempotentes | A | sí |
| 2 | Cupones/descuentos validados en servidor | M | sí |
| 3 | Carrito persistido + recuperación de abandonados (con consentimiento) | A | sí |
| 4 | Estado "pago en revisión" para comprobantes | M | quizá |
| 5 | Limpieza de deuda menor (TD5, TD10-TD14, test/ minitest) | B | drop table opcional |

---

## 11. Analytics y recuperación (recomendación consciente de privacidad)

**Hoy**: solo page views (`VisitorLog` por IP/path con geo) y snippet GA4 opcional con `anonymize_ip`, **sin eventos**. No se puede medir el funnel.

**Recomendación** (sin cookies de terceros, alineada al aviso de privacidad):
- Eventos servidor-side (modelo `AnalyticsEvent` o logs estructurados) para: `product_viewed`, `added_to_cart`, `removed_from_cart`, `checkout_started`, `checkout_validation_error`, `order_completed`, `cart_abandoned` (derivado: checkout_started sin order_completed en 24h, calculado por job, no en tiempo real).
- Sin fingerprinting; sesión anónima por id de sesión; IP solo agregada (ya existe VisitorLog); retención limitada (ya hay job de retención de visitor logs como patrón).
- Si se usa GA4 después: activar `gtag('event', ...)` solo con consentimiento del banner de cookies, que ya existe pero hoy no bloquea nada — decisión de negocio/legal.
- Prioridad Fase 3, complejidad Baja-Media, DB: sí (tabla de eventos) o ninguna si se usan logs.

---

## 12. Casos borde verificados

| Caso | Comportamiento actual | Veredicto |
|---|---|---|
| Producto sin stock tras agregarlo | Re-validado dos veces en checkout (con lock) con mensaje claro | ✅ Bien |
| Precio cambia durante la compra | Se cobra el precio del momento del checkout (promedio para coleccionables puede oscilar entre add y checkout) | ⚠ Aceptable; documentar/avisar |
| Más unidades que disponibles | Rechazado en add/update salvo `oversell_allowed?` (preventa) | ✅ Bien, pero el error no llega al usuario en carrito/mini-cart (TD2/TD3) |
| Producto inactivo en carrito | Rechazado al agregar; en checkout falla la revalidación | ⚠ No hay limpieza proactiva del carrito |
| Producto borrado | 404 en PDP; en carrito `Product.find` truena (404) | ⚠ Revisar path de carrito |
| Sesión expira | Carrito de sesión se pierde; checkout pide login | ⚠ Decisión: persistir carrito (Fase 4) |
| Login con carrito anónimo | Sobrevive (misma sesión) | ✅ Bien |
| Doble submit de checkout | Token + índice único; pre-chequeo OK; rescue de carrera roto (C2) | ⚠ Casi bien |
| Pago OK pero respuesta interrumpida | N/A hoy (pagos manuales); diseñar webhooks idempotentes en Fase 4 | ➖ Futuro |
| Pedido creado pero reserva falla | Tragado en producción (C5); job de reparación no programado (C4) | ❌ Mal |
| Envío no calculable | Calculator devuelve 0 silenciosamente | ⚠ Debería fallar explícito o etiquetarse |
| Descuento inválido | No hay cupones; `discount` solo admin | ➖ Futuro |
| Carrito en múltiples tabs | Cookie session: last-write-wins; races en qty (TD2, TD10) | ⚠ Aceptable tras TD2 |

---

## 13. Checklist de producción (carrito listo para pedidos reales)

**Dinero e inventario**
- [ ] Preorder reservations ligadas al pedido; sin creación de pedidos duplicados por el allocator (C1)
- [ ] Reserva atómica por pieza en todas las rutas (checkout, admin, jobs) (C13)
- [ ] Piezas en tránsito quedan `pre_reserved` (C8)
- [ ] `sold_price` correcto en cada pieza vendida (C6)
- [ ] Errores de reserva/pago hacen rollback o alertan — nada se traga (C5, C7)
- [ ] Job programado de expiración de reservas y auto-asignación (C4)
- [ ] Envío e impuestos del carrito == lo que cobra el checkout (§5.1)
- [ ] Disponibilidad mostrada == disponibilidad real en todas las vistas (TD8)

**Cliente**
- [ ] Email de confirmación enviado y verificado (C3)
- [ ] thank_you con estado de pago correcto (C9) y datos bancarios reales (C12)
- [ ] orders#show con instrucciones de pago y estado en español (§5.8, §5.5)
- [ ] Aceptación de Términos/Privacidad registrada (C11)
- [ ] Errores de cantidad/stock visibles en carrito y mini-cart (TD2, TD3)
- [ ] Carrito usable en móvil sin scroll horizontal (§7.1)

**Seguridad y privacidad**
- [ ] Tracking de listas WhatsApp no enumerable (C10)
- [ ] Doble-submit concurrente sin 500 (C2)
- [ ] Sin placeholders bancarios en producción (C12)

**Operación**
- [ ] Runbook: qué pasa cuando un pedido queda sin pago (expira), sin inventario (alerta), sin payment (reparación)
- [ ] Smoke test E2E en staging: browse → cart → checkout → pago → confirmación → email
- [ ] Specs de regresión para todos los items de Fase 1

---

## 14. Decisiones de negocio pendientes (bloquean partes del roadmap)

1. ¿Guest checkout sí/no? (Fase 3.1; hoy registro obligatorio)
2. ¿Precios visibles a invitados? (hoy inconsistente: card sí, PDP no)
3. TTL de reserva para pedidos sin pagar (sugerido 3-7 días por transferencia)
4. Regla real de envío (¿flat $99? ¿gratis ≥$1500? ¿por método?) e IVA (¿incluido en precio?)
5. Gateway de tarjeta objetivo y política de anticipos/parciales
6. Datos bancarios reales y texto legal definitivo de términos/devoluciones
7. ¿Recuperación de carritos abandonados por email? (implica carrito persistido + consentimiento)
