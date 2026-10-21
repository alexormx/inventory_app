# Conectar KataFrame a la API del inventario

KataFrame usa su conector **«API propia (REST)»**. El inventario expone
`/api/v1/products` con claves de API que se crean en el admin.

## 1. Crear la clave

Admin → **Sistema › Claves de API** → *Nueva clave*.

- Nombre: algo que identifique app y equipo («KataFrame – laptop»).
- Permisos:
  - **Leer productos** (`products:read`): listar y ver productos.
  - **Crear y editar productos** (`products:write`): crear, editar datos, publicar/despublicar.
  - **Subir fotos** (`photos:write`): agregar fotos (en crear o editar).

La clave (`pk_…`) se muestra **una sola vez**. Si se pierde, revócala y crea otra.
Revocar la desactiva al instante sin afectar a otras claves ni al token legado.

## 2. Configurar el conector en KataFrame

| Ajuste | Valor |
|---|---|
| Dirección | `https://pasatiempos.com.mx` |
| Encabezado / esquema | `Authorization` / `Bearer` |
| Token | la clave `pk_…` |
| Lista (GET) | `/api/v1/products` |
| Dónde viene la lista | `items` |
| Crear (POST) | `/api/v1/products` |
| Cambiar | `/api/v1/products/{id}` con `PATCH` |
| Envoltorio | `product` |
| Id | `id` |
| Fotos adjuntas | sí, campo `product[product_images][]` |
| Direcciones de las fotos | `image_urls` |

## 3. Qué hace cada operación

- **Listar**: todos los productos (borradores, inactivos y agotados incluidos),
  100 por página, siguiendo `next`. Filtro opcional `?updated_since=<ISO 8601>`.
- **Campos**: `id, code, product_name, brand, category, series, scale,
  selling_price, description, status, barcode, launch_date, stock_available,
  length_cm, width_cm, height_cm, weight_gr, custom_attributes, image_urls,
  updated_at`. Nunca se exponen SKU ni código de proveedor, costos ni proveedores.
- **Crear / editar**: campos escribibles `product_name, brand, category, series,
  scale, selling_price, description, barcode, launch_date, status,
  whatsapp_code, length_cm, width_cm, height_cm, weight_gr, custom_attributes`.
  Las existencias, costos y datos de proveedor no se pueden cambiar.
  - Productos nuevos reciben un SKU interno `KF…` (corregible en el admin).
  - `custom_attributes` se combina con lo existente; una llave vacía se borra.
  - Publicar (`status: active`) solo si hay existencias publicables, preventa o
    backorder; si no, `422`.
- **Fotos**: se agregan al final; la principal no cambia. Máximo 10 por
  petición y 15 MB por foto; JPG, PNG o WebP. Se guardan en tamaño original.
  KataFrame debería quitar EXIF/GPS antes de subir fotos de cámara.

## Errores

`401` clave inválida o revocada · `403` falta un permiso · `404` no existe ·
`422` validación (`{"errors": [...]}`).
