# Auditoría UI Admin · Marzo 2026

## Objetivo

Documentar el estado actual del panel administrativo, detectar inconsistencias visuales y definir una base clara para el rediseño incremental.

## Hallazgos principales

### 1. Identidad visual fragmentada
- El shell del admin usaba una paleta borgoña distinta al resto de superficies.
- Dashboard, formularios y sidebars de resumen tenían estilos y colores no alineados.
- Existían mezclas de `Bootstrap`, overrides globales y estilos inline.

### 2. Inconsistencias de idioma
- El layout usaba `lang="en"`.
- Había mezcla de textos en inglés y español en breadcrumbs, footer y páginas internas.

### 3. Jerarquía visual débil
- Sidebar, navbar y dashboard no compartían el mismo lenguaje visual.
- KPIs, badges y tablas funcionaban, pero con poca cohesión estilística.

### 4. Deuda técnica visual
- Mucho estilo inline en vistas del dashboard.
- Componentes repetidos con pequeñas variantes.
- Tokens globales y del admin no estaban claramente separados.

## Primera iteración implementada

### Shell admin
- `layout` del admin actualizado a español.
- Sidebar migrado a una paleta sobria azul pizarra.
- Navbar actualizado a superficies claras, badges neutros y mejor legibilidad.
- Footer actualizado en español y con año dinámico.

### Dashboard
- Header principal con mayor jerarquía visual.
- Quick actions más consistentes.
- KPI cards y mini-stats con clases semánticas reutilizables.

### Documentación
- Se crea esta auditoría.
- Se crea una guía base de design system.
- Se registran decisiones de diseño/arquitectura.

## Backlog visual recomendado

### Prioridad alta
1. Eliminar estilos inline restantes del dashboard.
2. Homologar formularios y sidebars de resumen de órdenes.
3. Normalizar idioma de reportes, settings y CRUDs históricos.

### Prioridad media
1. Consolidar tabs y pipelines compartidos.
2. Estandarizar tablas, headers de página y barras de filtros.
3. Revisar iconografía y densidad visual en listados complejos.

### Prioridad baja
1. Explorar dark mode específico del admin.
2. Crear vista de referencia para componentes visuales.
3. Añadir guideline de motion y microinteracciones.

## Archivos impactados en la primera iteración
- [app/views/layouts/admin.html.erb](app/views/layouts/admin.html.erb)
- [app/views/admin/partials/_sidebar.html.erb](app/views/admin/partials/_sidebar.html.erb)
- [app/views/admin/partials/_navbar.html.erb](app/views/admin/partials/_navbar.html.erb)
- [app/views/admin/partials/_footer.html.erb](app/views/admin/partials/_footer.html.erb)
- [app/assets/stylesheets/custom.scss](app/assets/stylesheets/custom.scss)
- [app/assets/stylesheets/dashboard.scss](app/assets/stylesheets/dashboard.scss)
- [app/views/admin/dashboard/index.html.erb](app/views/admin/dashboard/index.html.erb)
- [app/views/admin/dashboard/_kpi_card.html.erb](app/views/admin/dashboard/_kpi_card.html.erb)
- [app/views/admin/dashboard/_kpi_stat.html.erb](app/views/admin/dashboard/_kpi_stat.html.erb)