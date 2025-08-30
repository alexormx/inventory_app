# 🧰 Pasatiempos a Escala – Inventario & E‑Commerce (Rails 8)

Aplicación Rails 8 / Ruby 3.2.3 con enfoque en catálogo, carrito y gestión de inventario para productos coleccionables. Incluye optimizaciones recientes de rendimiento (imágenes responsive, carga diferida, modal de confirmación personalizada y actualización dinámica del carrito).

---
## 🔑 Stack Principal
| Área | Tecnología |
|------|------------|
| Framework | Rails 8.0.1 (Propshaft + Importmap + Hotwire) |
| Ruby | 3.2.3 |
| DB dev/test | SQLite |
| DB prod | PostgreSQL |
| Autenticación | Devise + roles (admin / customer) |
| Background / Cache | solid_queue / solid_cache / redis |
| Imágenes dinámicas | ActiveStorage + mini_magick + image_processing |
| Estilos | Bootstrap 5.3 + Sass |
| Tests | RSpec, Capybara, FactoryBot |

---
## ✅ Features Clave Implementadas
1. Autenticación y roles (Devise) con campos adicionales de perfil.
2. Dashboard administrador y secciones de inventario / productos (en progreso iterativo).
3. Catálogo público con paginación (`kaminari`) y filtros básicos.
4. Carrito con actualización dinámica (Stimulus + respuestas JSON):
  - Recalcula subtotal, impuestos, envío, totales y desglose de pendientes en vivo.
  - Elimina duplicidad de badges (preventa / sobre pedido) mostrando badge unificado.
5. División disponibilidad: helper `stock_badge` y `stock_eta` calculan inmediato vs. preorder/backorder.
6. Modal de confirmación reutilizable (Stimulus `confirm_controller`) reemplaza `data-turbo-confirm`.
7. Galería de producto con cambio de imagen principal (Stimulus `gallery_controller`).
8. Optimización de imágenes:
  - Helpers responsive: `responsive_asset_image` (estáticas) y `responsive_attachment_image` (ActiveStorage).
  - Generación condicional de `<picture>` con fuentes AVIF/WebP si existen.
  - `fetchpriority="high"` y `<link rel="preload">` para LCP en show de producto.
  - Lazy loading + `decoding="async"` + dimensiones calculadas para evitar CLS.
  - Rake task para pre-generar variantes modernas en assets estáticos.
9. Banner de cookies configurable vía variables de entorno.
10. SEO básico: meta tags OG/Twitter, sitemap (`sitemap_generator`), `robots.txt`.

---
## 🖼️ Helpers de Imágenes Responsive
### 1. Assets estáticos
```erb
<%= responsive_asset_image 'collection_shelf.jpg', alt: 'Colección', css_class: 'img-fluid', aspect_ratio: '16:9', widths: [480,768,1200] %>
```
Genera `<picture>` con `<source>` AVIF/WebP si `collection_shelf.avif|webp` existen, y fallback `<img>` con atributos de accesibilidad y rendimiento.

### 2. ActiveStorage (productos)
```erb
<%= responsive_attachment_image product.product_images.first,
    alt: product.product_name,
    widths: [160,200,320,400],
    css_class: 'product-image',
    square: true %>
```
Produce variantes on‑demand (limitadas por ancho) y fuentes modernas si mini_magick soporta el formato.

---
## ⚙️ Tarea para Generar AVIF/WebP en Assets
Convierte imágenes grandes (>.150KB) en `app/assets/images` a `*.avif` y `*.webp` si no existen.
```bash
bin/rails images:generate_modern_formats
```
Luego precompilar (si aplica) o reiniciar el servidor para que se detecten.

---
## 🛒 Carrito Dinámico
- Controlador Stimulus `cart-item` escucha cambios de cantidad y destruye ítems vía fetch/Turbo Streams.
- Respuesta JSON del backend incluye totales globales y desglose de inmediato vs. pendiente.
- Accesibilidad: región `aria-live` en totales de línea.

---
## 🔐 Disponibilidad / Etiquetas de Stock
`stock_badge(product, quantity:)` produce un solo badge coherente (En stock / Preventa / Sobre pedido / Fuera de stock) con tooltip + nota de pendientes opcional.

---
## 🧪 Testing (Resumen Actual)
- Autenticación / roles (RSpec).
- Controladores básicos admin.
- (Pendiente ampliar) pruebas para helpers de imágenes y carrito.

---
## 🚀 Roadmap Próximo (Short-Term)
| Prioridad | Ítem | Objetivo |
|-----------|------|----------|
| Alta | Medir impacto Lighthouse (performance, LCP, CLS) | Verificar ganancias tras imágenes responsive |
| Alta | Añadir tests de helpers (`responsive_*`) | Evitar regresiones |
| Media | Pre-cálculo de variantes críticas en deploy | Reducir primer tiempo de generación |
| Media | Mejorar regeneración dinám. de `<source>` en galería | Mantener formatos modernos al cambiar imagen |
| Media | Instrumentar logging de tiempos de variante | Identificar imágenes lentas |
| Baja | i18n de tooltips adicionales | Consistencia multi-idioma |

---
## 📝 Variables de Entorno Destacadas
| Variable | Descripción | Default |
|----------|-------------|---------|
| COOKIE_BANNER_ENABLED | Mostrar banner cookies | true |
| COOKIE_BANNER_TEXT | Texto banner | Español por defecto |
| COOKIE_BANNER_BUTTON_TEXT | Texto botón | Aceptar |
| PREORDER_ETA_DAYS / BACKORDER_ETA_DAYS (SiteSetting) | Cálculo ETA | 60 |

---
## 🧪 Comandos Útiles
```bash
# Ejecutar servidor desarrollo (Procfile.dev si se usa foreman)
bin/dev

# Generar variantes modernas assets
bin/rails images:generate_modern_formats

# Sitemap
bin/rails sitemap:generate

# Tests
bundle exec rspec
```

---
## ♿ Accesibilidad / UX
- Botones con `aria-label` en carrito y acciones clave.
- Eliminado uso de confirm nativo; modal accesible con cierre por ESC y click en backdrop.
- Etiquetas alt consistentes para todas las imágenes generadas por helpers.

---
## 🔒 Seguridad / Buenas Prácticas
- CSRF y CSP tags activos.
- Uso de `allow_browser versions: :modern` para reducir superficie legacy.
- Limpieza silenciosa de errores en procesamiento de imágenes evitando caídas front.

---
## 📈 Métricas a Monitorear (sugerido)
- LCP: imagen principal de producto / primera card en home.
- CLS: verificar tras widths/height calculados.
- Transfer size total de homepage antes/después (objetivo < 500KB inicial).

---
## 🤝 Contribuir
1. Crear rama `feat/...` o `fix/...`.
2. Ejecutar tests y Lighthouse local si cambia UI.
3. Pull Request con descripción de impacto (UX, perf, seguridad).

---
## ✨ Créditos
Proyecto interno Pasatiempos a Escala. Uso educativo y de demostración de mejores prácticas Rails + optimización de frontend sin empaquetadores pesados.
