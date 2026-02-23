# Fixes de guardado de producto y eliminación de imágenes

**Fecha:** 21 de febrero, 2026
**Áreas:** Admin Products (`create/update`), Stimulus `confirm_controller`, ActiveStorage image purge

## Resumen

Se corrigieron dos incidencias reportadas en producción:

1. **"Guardar producto no guarda"** al crear productos con campos numéricos vacíos.
2. **"Eliminar imagen no elimina"** desde la pantalla de edición de producto.

## 1) Bug: creación de producto no persistía

### Síntoma
- En `POST /admin/products` el flujo respondía `200 OK` con re-render del formulario, sin redirect de éxito.
- Desde UI se percibía como "no se guardó".

### Causa raíz
- El campo `maximum_discount` llegaba como string vacío (`""`) desde el formulario.
- El modelo exige `presence` y `numericality` para `maximum_discount`, por lo que la validación fallaba.

### Solución aplicada
- Se agregó normalización previa a validación en `Product`:
  - `maximum_discount` vacío → `0`
  - `discount_limited_stock` vacío → `0`
  - `reorder_point` vacío → `0`
- Se mejoró el mensaje de error en `Admin::ProductsController#create/update` para mostrar `full_messages` y facilitar diagnóstico.

## 2) Bug: eliminación de imagen en editar producto

### Síntoma
- Al intentar borrar una imagen desde `edit`, no se ejecutaba el `DELETE` esperado.

### Causa raíz
- El trigger de confirmación en un enlace dentro de un formulario podía terminar enviando el submit del form padre (`PATCH`) en lugar de respetar el `turbo_method: :delete` del link.

### Solución aplicada
- En `app/javascript/controllers/confirm_controller.js`, al confirmar sobre un `<a>` con método no `GET`, se prioriza la acción del enlace y se envía un form dedicado con `_method` correspondiente.

## Cobertura de pruebas

### Nuevas pruebas
- Request spec para creación de producto con `maximum_discount` vacío, verificando persistencia y normalización a `0`.
- Request specs para `DELETE /admin/products/:id/images/:image_id` en HTML y Turbo Stream, verificando purga real del adjunto y respuesta esperada.

### Ejecución recomendada

```bash
bundle exec rspec spec/requests/admin_products_spec.rb
```

## Nota operativa

- Este fix reduce errores "silenciosos" en formularios y deja trazabilidad más clara para soporte cuando una validación impide guardar.