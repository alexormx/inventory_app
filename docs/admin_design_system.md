# Design System Admin

## Principios

1. **Claridad operativa**: priorizar lectura rápida y densidad controlada.
2. **Sobriedad visual**: navegación oscura, contenido claro, acentos discretos.
3. **Consistencia**: un mismo patrón para cards, tablas, badges, filtros y navegación.
4. **Escalabilidad**: evitar estilos inline y favorecer clases semánticas reutilizables.

## Paleta base

### Navegación
- Fondo sidebar: `#0f172a`
- Fondo activo: `#111c36`
- Texto principal: `#f8fafc`
- Texto secundario: `#94a3b8`
- Acento activo: `#38bdf8`

### Contenido
- Fondo general: `#f3f6fb`
- Superficie principal: `#ffffff`
- Superficie suave: `#f8fafc`
- Borde: `rgba(15, 23, 42, 0.08)`
- Texto principal: `#0f172a`
- Texto secundario: `#64748b`
- Acento funcional: `#0f766e`

## Componentes

### Shell
- `admin-shell`: contexto global del panel.
- `admin-main`: superficie principal del contenido.
- `admin-footer`: pie consistente y discreto.

### Navegación
- Sidebar con secciones nominales (`Resumen`, `Operación`, `Catálogo e inventario`, `Finanzas y análisis`, `Sistema`).
- Navbar clara con breadcrumb, badge contextual y acciones de perfil/salida.

### Dashboard
- `admin-page-header`: bloque hero de encabezado.
- `admin-page-eyebrow`: contexto superior pequeño.
- `admin-page-badge`: badge de periodo.
- `admin-kpi-card`: KPI principal.
- `admin-kpi-stat`: estadística táctica.

## Reglas visuales

### Radios
- Grandes superficies: `1rem`
- Chips y botones compactos: `999px`
- Sidebar items: `0.8rem`

### Sombras
- Surface ligera: `var(--admin-shadow-sm)`
- Surface media: `var(--admin-shadow-md)`

### Tipografía
- Labels de KPI y tablas: uppercase sutil y tracking leve.
- Texto secundario siempre en tono pizarra.
- Títulos de página con peso alto y acompañamiento contextual.

## Reglas de implementación

1. No agregar estilos inline nuevos si existe un patrón reutilizable.
2. Preferir clases semánticas antes que cadenas largas de utilidades cuando el patrón se repita.
3. Mantener compatibilidad con Turbo y Stimulus al ajustar navegación.
4. Evitar depender solo del color para comunicar estado.

## Próximos componentes a sistematizar
- Filter bars
- Summary sidebars de órdenes
- Status counters
- Tabs admin
- Empty states
- Encabezados CRUD