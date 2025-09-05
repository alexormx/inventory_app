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
8. Optimización de imágenes (fases 1 y 2):
  - Helpers: `responsive_asset_image` (assets estáticos multi‑width) y `responsive_attachment_image` (ActiveStorage AVIF/WebP si disponibles).
  - Variantes multi‑anchos pre-generadas (`nombre-480w.webp` etc.) + `<picture>` / fallback.
  - Preload LCP (home + producto) con helpers (`lcp_preload_home_image`, `lcp_preload_product_image`) y `fetchpriority="high"`.
  - Lazy loading + `decoding="async"` + tamaños calculados para minimizar CLS.
  - Rake tasks: `images:generate_modern_formats` y `images:generate_responsive_variants`.
9. Galería avanzada (loop infinito, clones, thumbnails accesibles como botones, navegación teclado, transición suave).
10. Lazy hydration de JS no crítico (cola `requestIdleCallback` + fallback `load`).
11. Font Awesome diferido + override `font-display: swap`.
12. ECharts cargado perezosamente (dynamic import) sólo si hay charts.
13. Índices de rendimiento y preload de attachments para evitar N+1.
14. Memoización de stock y badge unificado.
15. Banner de cookies configurable vía variables.
16. SEO básico: meta tags OG/Twitter, sitemap (`sitemap_generator`), `robots.txt`.

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
## 🚀 Roadmap Próximo
| Prioridad | Ítem | Objetivo |
|-----------|------|----------|
| Alta | Fragment caching (cards catálogo, show producto) | Menos render repetido / menor TTFB |
| Alta | Medir impacto Lighthouse post fase 2 | Ajustar budgets y validar LCP/CLS reales |
| Alta | Tests helpers `responsive_*` & galería | Prevenir regresiones perf/HTML accesible |
| Alta | Job de pre-cálculo variantes críticas (on deploy / background) | Evitar primer coste de generación en frío |
| Media | CDN / Headers cache (Cache-Control, immutable) | Mejor hit ratio y menor coste ancho de banda |
| Media | Instrumentar tiempos y ratio hit de variantes | Detectar imágenes candidates a pre-generar |
| Media | Actualizar dinámicamente `<source>` en galería al cambiar imagen | Mantener formatos modernos y srcset correcto |
| Media | ECharts build liviano / alternativa (charts light) | Reducir JS diferido y CPU post-hydration |
| Baja | i18n tooltips y textos menores | Pulido UX multi-idioma |
| Baja | Skeleton / placeholder para imágenes LCP en conexiones lentas | Mejor percepción de carga |

---
## 📝 Variables de Entorno Destacadas
| Variable | Descripción | Default |
|----------|-------------|---------|
| COOKIE_BANNER_ENABLED | Mostrar banner cookies | true |
| COOKIE_BANNER_TEXT | Texto banner | Español por defecto |
| COOKIE_BANNER_BUTTON_TEXT | Texto botón | Aceptar |
| PREORDER_ETA_DAYS / BACKORDER_ETA_DAYS (SiteSetting) | Cálculo ETA | 60 |

---
## 🔍 Página Admin: System Variables
Ruta: `/admin/system_variables` (link en la sección “System” del sidebar).

Objetivo: Visibilidad centralizada y sin exponer secretos de:
- ENV filtradas (omite llaves que contengan: SECRET, PASSWORD, KEY, TOKEN, DATABASE_URL, RAILS_MASTER_KEY)
- SiteSettings persistidos en DB
- Sub‑conjunto de configuración Rails (cache_store, servicio ActiveStorage, eager_load, etc.)
- Info runtime (Ruby/Rails version, PID, memoria, timestamp)
- Banderas dinámicas / toggles simples (ej: banner de cookies)

Características:
- Scroll interno en listas largas para evitar crecer verticalmente la página.
- Diseño sólo lectura (por ahora) para minimizar riesgo de cambios accidentales.
- Estructura preparada para extender con métricas (solid_queue depth, Redis info, cache hit ratio, etc.)

Extender / Personalizar:
1. Agregar nueva sección: crear método privado en `Admin::SystemVariablesController` y añadir card en la vista `app/views/admin/system_variables/index.html.erb`.
2. Exportar JSON: añadir acción `def export` que renderice un hash agregado y link en la UI (pendiente opcional).
3. Métricas de colas (ejemplo):
   ```ruby
   def queue_metrics
     { pending_jobs: SolidQueue::Job.pending.count }
   end
   ```
4. Redis stats: usar `Redis.current.info.slice('used_memory_human','connected_clients')` (manejar rescue si no disponible).

Seguridad:
- Nunca mostrar valores completos de llaves sensibles; si se requiere listar su presencia, usar enmascarado (`****suffix`).
- Revisión antes de añadir nuevas expresiones regulares en `SENSITIVE_ENV_PATTERNS`.

Testing sugerido (pendiente):
- Request spec que garantice exclusión de variables sensibles mockeadas.
- System spec que verifique presencia de secciones clave y ausencia de patrones `SECRET`.

Próximos incrementos recomendados:
- Botón “Copiar todo” (clipboard) para reporte técnico.
- Endpoint JSON firmado sólo para admins (auditoría / soporte).
- Indicadores de modo (development / production) resaltados visualmente.

### 🗂 Data Dictionary / Descripciones de Tablas y Columnas
Se mantiene en `db/schema_docs.yml` (dev) y opcionalmente en comentarios nativos de PostgreSQL para prod.

Workflows:
1. Generar / actualizar placeholders:
  ```bash
  bin/rails introspection:generate_schema_docs
  ```
  Esto añade entradas faltantes sin borrar comentarios existentes.
2. Editar manualmente `db/schema_docs.yml` rellenando `_comment` (tabla) y cada columna.
3. (Opcional Postgres) Aplicar comentarios a la BD:
  ```bash
  bin/rails introspection:apply_comments
  ```
4. Ver progreso:
  ```bash
  bin/rails introspection:dictionary_progress
  ```

Placeholders: se generan como `TODO: describir ...` si está vacío. Puedes buscar rápidamente lo pendiente:
```bash
grep -R "TODO: describir" db/schema_docs.yml
```

Estrategia recomendada de llenado:
- Empezar por tablas de dominio crítico (orders, products, users).
- Describir el propósito en 1 frase (`_comment`).
- Para columnas: foco en semántica funcional, unidades (cents, UTC, etc.) y restricciones implícitas no expresadas por el esquema.
- Evitar repetir lo obvio ("id primary key").

Sincronización con Postgres: Los comentarios en la DB aparecen también en la UI (mezclados con YAML). YAML tiene precedencia si existe.



---
## 🧪 Comandos Útiles
```bash
# Ejecutar servidor desarrollo (Procfile.dev si se usa foreman)
bin/dev

# Generar variantes modernas assets
bin/rails images:generate_modern_formats

# Generar variantes responsive (multi-width) predefinidas
bin/rails images:generate_responsive_variants

# Sitemap
bin/rails sitemap:generate

# Tests
bundle exec rspec

# Lighthouse CI (local)
export LH_PRODUCT_PATH=/products/1 # o URL completa
LH_PRODUCT_PATH=$LH_PRODUCT_PATH npx lhci autorun
```

### Budgets Lighthouse
Definidos en `lighthouse-budgets.json` para limitar peso total e imágenes; assertions extra agregadas:
- LCP ≤ 2500ms
- CLS ≤ 0.1
- Total transfer home ≤ ~550KB (warning si supera)
- Página producto incluida en budgets (`/products/placeholder-slug`); reemplaza el slug en `lighthouse-budgets.json` y variable `LH_PRODUCT_PATH` para CI.

---
## ♿ Accesibilidad / UX
- Botones con `aria-label` en carrito y acciones clave.
- Modal de confirmación accesible (ESC, foco retornado, backdrop clickable) en lugar de confirm nativo bloqueante.
- Thumbnails de galería como `<button>` (no `<a href="#">`), foco visible, navegación teclado circular.
- Región `aria-live` para actualización de totales de carrito (sin anunciar valores irrelevantes).
- Alt text consistente generado desde `product.product_name` o parámetros explícitos.
- Prevención de CLS: dimensiones calculadas / estilos placeholders.
- Cursor y feedback visual claro en elementos interactivos (thumbnails, badges).

---
## 🔒 Seguridad / Buenas Prácticas
- CSRF y CSP activos.
- `allow_browser versions: :modern` para reducir superficie legacy / polyfills.
- Sanitización de URLs de ActiveStorage (removiendo segmento de locale y queries no necesarios) para evitar 302 y rutas inconsistentes.
- Manejo controlado de errores en procesamiento de variantes (fail-soft) sin filtrar trazas a usuario.
- Dependencias JS minimizadas (dynamic import) reduciendo superficie de ataque potencial.

---
## 📈 Métricas a Monitorear (sugerido)
- LCP: imagen principal de producto / primera card en home.
- CLS: verificar tras widths/height calculados.
- Transfer size total de homepage antes/después (objetivo < 500KB inicial).
 - % de imágenes servidas en formato moderno (AVIF/WebP) vs. JPEG.
 - Tiempo medio generación primera variante vs. cache hit (objetivo: reducir cold start tras job pre-cálculo).
 - Peso JS inicial vs. diferido tras lazy hydration / dynamic import.
 - TTFB en show producto tras fragment caching (baseline antes de implementarlo).

---
## 🧾 Changelog Optimización (resumen)
| Fase | Tema | Cambios clave |
|------|------|---------------|
| 1 | Imágenes base | Helpers responsive, AVIF/WebP assets, preload LCP inicial |
| 2 | Perf avanzado | Galería loop accesible, lazy hydration, dynamic import ECharts, font-display swap, variantes multi-width, tasks pre-generación |
| 2 | Backend | Índices rendimiento, preload attachments, memoización stock |
| 2 | UX | Modal confirm accesible, badges unificados, thumbnails clicables |
| 2 | URL Sanitization | Remoción locale en rutas ActiveStorage evitando errores |

---
## 🤝 Contribuir
1. Crear rama `feat/...` o `fix/...`.
2. Ejecutar tests y Lighthouse local si cambia UI.
3. Pull Request con descripción de impacto (UX, perf, seguridad).

---
## ✨ Créditos
Proyecto interno Pasatiempos a Escala. Uso educativo y de demostración de mejores prácticas Rails + optimización de frontend sin empaquetadores pesados.
