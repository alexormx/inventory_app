# Mercado Pago — Checkout Pro

El cliente elige "Mercado Pago" en el paso 3, se crea el pedido (inventario
apartado, pago `Pending`) y se le redirige a Mercado Pago. Al pagar regresa a
`/checkout/mercado_pago/return`; el webhook confirma el pago aunque no regrese.

## Configuración (la hace una persona, nunca un agente)

1. Panel de desarrolladores de Mercado Pago → crear aplicación (Checkout Pro).
2. Cargar credenciales en Heroku **sin imprimirlas**:
   - `MERCADOPAGO_ACCESS_TOKEN` (de prueba primero, luego producción)
   - `MERCADOPAGO_WEBHOOK_SECRET` (Webhooks → clave secreta)
3. Webhooks → URL `https://pasatiempos.com.mx/webhooks/mercado_pago`, evento **Pagos**.
   (Cada preferencia también manda `notification_url` con esa misma ruta.)
4. Admin → Configuración → Métodos de pago → activar "Mercado Pago".
   Sin `MERCADOPAGO_ACCESS_TOKEN` no aparece en el checkout aunque esté activo.

## Modo prueba

- Con credenciales `TEST-...` (o `MERCADOPAGO_TEST_MODE=true`, útil con las de
  un usuario vendedor de prueba) Mercado Pago **solo lo ven los admins** y no se
  manda el correo real del cliente.
- Con credenciales de un **usuario vendedor de prueba** Mercado Pago responde
  `live_mode: true`; por eso, con `MERCADOPAGO_TEST_MODE=true`, **todo** pago se
  trata como de prueba. Fuera de modo prueba, todo pago con `live_mode: false` es de prueba: nunca pasa a `Completed`, y si
  se aprueba el pedido se **cancela solo** (libera inventario, sale de los
  reportes) con la nota "Pedido de prueba". En el admin lleva la etiqueta *Prueba*.
- Al pasar a producción: cargar el Access Token de producción y quitar
  `MERCADOPAGO_TEST_MODE` si se usó.

## Cómo se decide que un pago está cobrado

Solo `MercadoPago::SyncPayment`, consultando `GET /v1/payments/:id` en la API:
nunca el `status` de la URL de regreso ni el cuerpo del webhook.

| Estado en Mercado Pago | `payments.status` |
|---|---|
| `approved` (monto y MXN coinciden) | `Completed` → pedido `Confirmed` |
| `approved` con monto distinto | sigue `Pending`, `provider_status = amount_mismatch` |
| `pending`, `in_process` (OXXO/SPEI) | `Pending` |
| `rejected`, `cancelled` | `Pending` (el cliente puede reintentar) |
| `refunded`, `charged_back` | `Refunded` |

## Avisos (webhooks)

- Solo se procesan los Webhooks firmados (`?data.id=…&type=payment`). Sin
  `MERCADOPAGO_WEBHOOK_SECRET` todos se rechazan con 401 y los pagos de
  OXXO/SPEI nunca se confirmarían.
- Los avisos IPN viejos (`?id=…&topic=…`) no traen firma: se responden 200 sin procesar.

## OXXO / SPEI

El pago queda `pending` con la ficha en `transaction_details.external_resource_url`.
Se guarda en `payments.provider_ticket_url`, se manda por correo una vez
(`OrderConfirmationMailer#mercado_pago_ticket`) y se muestra el botón
"Ver ficha de pago". Al pagarse llega el webhook `approved` y el pedido se confirma.

## Re-sincronizar un pago

    heroku run rake 'mercado_pago:resync[PAYMENT_ID]'

## Pendiente (siguientes PRs)

- Vencimiento del apartado de inventario para pagos OXXO/SPEI no realizados.
- Datos de Mercado Pago y reembolsos en el admin del pedido.
