# Dashboard UI/UX - Propuesta de Mejoras

## Análisis General

El dashboard actual es funcional pero presenta oportunidades significativas de mejora en jerarquía visual, espaciado, tipografía y distribución. Este documento proporciona recomendaciones específicas para optimizar la experiencia del usuario.

---

## 🎯 Prioridades de Mejora

### 1. JERARQUÍA VISUAL

#### Problema Actual
- **KPIs dispersos**: Múltiples filas de KPIs sin clara jerarquía (línea 5-55, 107-127, 130-155)
- **Tamaños inconsistentes**: Cards de métricas principales vs tácticas no diferenciadas claramente
- **Falta de énfasis**: No se destacan los KPIs más importantes (Ventas, Ganancia, Margen)

#### Soluciones Propuestas

**A. Estructura de 3 niveles:**
```
1. Hero KPIs (Estratégicos) - MÁS GRANDES
   ├─ Ventas YTD
   ├─ Ganancia YTD
   └─ Margen YTD

2. KPIs Secundarios - MEDIANOS
   ├─ Compras Totales
   ├─ Clientes Activos
   └─ Valor Inventario

3. KPIs Tácticos - PEQUEÑOS/COMPACTOS
   ├─ Ticket promedio
   ├─ Conversión
   ├─ Stock crítico
   └─ Recurrentes
```

**B. Rediseño visual de cards:**

```erb
<!-- Hero KPI (más grande, más espacio) -->
<div class="col-lg-4">
  <div class="card border-0 shadow-sm <%= variant %> h-100">
    <div class="card-body p-4"> <!-- Más padding -->
      <div class="small text-uppercase text-muted mb-2 fw-semibold letter-spacing-1">
        <%= title %>
      </div>
      <div class="display-5 fw-bold mb-2"> <!-- Display size para hero -->
        <%= value %>
      </div>
      <div class="d-flex align-items-center gap-3">
        <span class="badge <%= delta_badge_class(delta) %> px-2 py-1">
          <i class="fa <%= delta_icon(delta) %> me-1"></i>
          <%= format_delta(delta) %>
        </span>
        <span class="small text-muted">vs LY: <%= ly %></span>
      </div>
    </div>
  </div>
</div>

<!-- KPI Secundario (mediano) -->
<div class="col-md-4">
  <div class="card border-0 shadow-sm <%= variant %> h-100">
    <div class="card-body p-3">
      <div class="small text-muted mb-1"><%= title %></div>
      <div class="fs-3 fw-bold mb-1"><%= value %></div>
      <% if delta %>
        <div class="badge <%= delta_badge_class(delta) %>">
          <%= format_delta(delta) %>
        </div>
      <% end %>
    </div>
  </div>
</div>

<!-- KPI Táctico (compacto, estilo mini-stat) -->
<div class="col-6 col-md-3">
  <div class="card border-0 bg-white h-100">
    <div class="card-body p-2 px-3">
      <div class="text-muted small mb-0"><%= title %></div>
      <div class="fs-5 fw-semibold"><%= value %></div>
    </div>
  </div>
</div>
```

---

### 2. ESPACIADO Y RITMO VISUAL

#### Problemas Actuales
- `g-3` uniforme en todas las filas (líneas 5, 58, 107, 130)
- Poco "respiro" entre secciones importantes
- Cards se ven muy juntas en desktop

#### Soluciones

**A. Espaciado progresivo:**

```erb
<!-- Hero section: más espacio arriba/abajo -->
<div class="row g-3 g-lg-4 mb-4">
  <!-- Hero KPIs -->
</div>

<!-- Sección secundaria: espacio moderado -->
<div class="row g-3 mb-4 pt-2">
  <!-- Secondary KPIs -->
</div>

<!-- Sección táctica: compacta -->
<div class="row g-2 mb-3">
  <!-- Tactical mini-stats -->
</div>

<!-- Separador visual entre secciones mayores -->
<hr class="my-5 border-2 opacity-10">

<!-- Productos & Inventario -->
<div class="row g-3 g-xl-4 mb-4">
  <!-- ... -->
</div>
```

**B. Padding interno ajustado por importancia:**
- Hero cards: `p-4` (más espacio)
- Secondary cards: `p-3` (moderado)
- Tactical cards: `p-2 px-3` (compacto)

---

### 3. TIPOGRAFÍA

#### Problemas Actuales
- Títulos de cards sin peso visual claro
- `fs-4`, `fs-6` mezclados sin sistema
- Falta de distinción entre valores primarios y secundarios

#### Sistema Tipográfico Propuesto

```scss
// En custom.scss o similar
.dashboard {
  // Hero values
  .hero-value {
    font-size: 2.5rem;     // ~40px
    font-weight: 700;
    line-height: 1.2;
  }

  // Secondary values
  .secondary-value {
    font-size: 1.75rem;    // ~28px
    font-weight: 600;
    line-height: 1.3;
  }

  // Tactical values
  .tactical-value {
    font-size: 1.25rem;    // ~20px
    font-weight: 600;
    line-height: 1.4;
  }

  // Labels
  .label-hero {
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--bs-secondary);
  }

  .label-standard {
    font-size: 0.8125rem;
    font-weight: 500;
    color: var(--bs-secondary);
  }
}
```

**Aplicación:**

```erb
<div class="card-body p-4">
  <div class="label-hero mb-2"><%= title %></div>
  <div class="hero-value text-primary"><%= value %></div>
  <div class="d-flex align-items-center gap-2 mt-2">
    <span class="badge bg-success-subtle text-success border border-success-subtle">
      <i class="fa fa-arrow-up me-1"></i>
      <%= format_delta(delta) %>
    </span>
    <span class="label-standard">vs año pasado</span>
  </div>
</div>
```

---

### 4. COLOR Y CONTRASTE

#### Problemas Actuales
- Variantes `-subtle` reducen contraste innecesariamente
- Deltas no usan color para comunicar positivo/negativo efectivamente
- Falta de sistema de color consistente

#### Sistema de Color Propuesto

```erb
<!-- Helper method en controller o helper -->
<%
def kpi_variant(title)
  case title
  when /Ventas|Ingresos/i
    'border-start border-5 border-success'
  when /Ganancia|Utilidad/i
    'border-start border-5 border-primary'
  when /Margen/i
    'border-start border-5 border-warning'
  when /Inventario/i
    'border-start border-5 border-info'
  else
    'border-start border-2 border-secondary'
  end
end

def delta_badge_class(delta)
  return 'bg-light text-muted' unless delta
  delta >= 0 ? 'bg-success-subtle text-success border border-success' : 'bg-danger-subtle text-danger border border-danger'
end
%>

<!-- Aplicación -->
<div class="card bg-white shadow-sm <%= kpi_variant(title) %> h-100">
  <div class="card-body p-4">
    <div class="label-hero mb-2"><%= title %></div>
    <div class="hero-value"><%= value %></div>
    <% if delta %>
      <span class="badge <%= delta_badge_class(delta) %> mt-2">
        <i class="fa <%= delta >= 0 ? 'fa-arrow-up' : 'fa-arrow-down' %> me-1"></i>
        <%= number_to_percentage(delta.abs * 100, precision: 1) %>
      </span>
    <% end %>
  </div>
</div>
```

---

### 5. DISTRIBUCIÓN Y LAYOUT

#### Problemas Actuales
- 6 KPIs en la primera fila (línea 5-55) sobrecarga visualmente
- Col sizes inconsistentes: `col-md-4 col-lg-3` mezclado con `col-md-2 col-6`
- Tablas con tabs anidados crean complejidad cognitiva

#### Grid System Optimizado

```erb
<!-- Hero Section: 3 columnas desktop, 1 mobile -->
<div class="row g-3 g-lg-4 mb-4">
  <div class="col-12 col-lg-4">
    <%= render "kpi_hero", title: "Ventas YTD", value: @sales_ytd, delta: @kpi_deltas[:sales] %>
  </div>
  <div class="col-12 col-lg-4">
    <%= render "kpi_hero", title: "Ganancia YTD", value: @profit_ytd, delta: @kpi_deltas[:profit] %>
  </div>
  <div class="col-12 col-lg-4">
    <%= render "kpi_hero", title: "Margen YTD", value: @margin_ytd, delta: @kpi_deltas[:margin_pp] %>
  </div>
</div>

<!-- Secondary Section: 3 columnas consistentes -->
<div class="row g-3 mb-4 pt-2">
  <div class="col-md-6 col-lg-4">
    <%= render "kpi_secondary", title: "Clientes Activos", value: @active_customers_ytd %>
  </div>
  <div class="col-md-6 col-lg-4">
    <%= render "kpi_secondary", title: "Valor Inventario", value: @inventory_total_value %>
  </div>
  <div class="col-md-6 col-lg-4">
    <%= render "kpi_secondary", title: "Compras Totales", value: @purchases_total_mxn %>
  </div>
</div>

<!-- Tactical Grid: 4 columnas desktop, 2 mobile -->
<div class="row g-2 mb-4">
  <div class="col-6 col-lg-3">
    <%= render "kpi_tactical", title: "Ticket Promedio", value: @avg_ticket_ytd %>
  </div>
  <div class="col-6 col-lg-3">
    <%= render "kpi_tactical", title: "Conversión", value: @conversion_rate_ytd %>
  </div>
  <div class="col-6 col-lg-3">
    <%= render "kpi_tactical", title: "Stock Crítico", value: @critical_stock_count %>
  </div>
  <div class="col-6 col-lg-3">
    <%= render "kpi_tactical", title: "% Recurrentes", value: @recurring_customers_ratio %>
  </div>
</div>
```

---

### 6. SIMPLIFICACIÓN DE TABS

#### Problema
- 3 niveles de tabs anidados (Productos > Vendedores/Rentables > YTD/LY/All)
- Dificulta navegación y sobrecarga cognitiva

#### Solución: Tabs con botones de período flotantes

```erb
<div class="card h-100">
  <div class="card-header d-flex justify-content-between align-items-center border-bottom-0 pb-0">
    <div>
      <h5 class="mb-0"><i class="fa-solid fa-box me-2 text-primary"></i>Top Productos</h5>
      <p class="text-muted small mb-0">Por unidades vendidas</p>
    </div>
    <!-- Período selector como dropdown compacto -->
    <div class="btn-group btn-group-sm" role="group">
      <input type="radio" class="btn-check" name="period-sellers" id="period-sellers-ytd" autocomplete="off" checked>
      <label class="btn btn-outline-secondary" for="period-sellers-ytd">YTD</label>

      <input type="radio" class="btn-check" name="period-sellers" id="period-sellers-ly" autocomplete="off">
      <label class="btn btn-outline-secondary" for="period-sellers-ly">LY</label>

      <input type="radio" class="btn-check" name="period-sellers" id="period-sellers-all" autocomplete="off">
      <label class="btn btn-outline-secondary" for="period-sellers-all">All</label>
    </div>
  </div>

  <!-- Subtabs: solo 2 opciones, más prominentes -->
  <div class="card-body pt-2">
    <ul class="nav nav-pills nav-fill mb-3" role="tablist">
      <li class="nav-item">
        <button class="nav-link active" data-bs-toggle="tab" data-bs-target="#sellers">
          <i class="fa fa-chart-line me-1"></i> Top Vendedores
        </button>
      </li>
      <li class="nav-item">
        <button class="nav-link" data-bs-toggle="tab" data-bs-target="#profitable">
          <i class="fa fa-dollar-sign me-1"></i> Más Rentables
        </button>
      </li>
    </ul>

    <div class="tab-content">
      <div class="tab-pane fade show active" id="sellers">
        <!-- Turbo frame con data dinámico -->
      </div>
      <div class="tab-pane fade" id="profitable">
        <!-- Turbo frame con data dinámico -->
      </div>
    </div>
  </div>
</div>
```

---

### 7. MICRO-INTERACCIONES Y FEEDBACK

#### Mejoras Propuestas

**A. Loading states más elegantes:**

```erb
<!-- En lugar de spinner básico -->
<div class="text-center py-4">
  <div class="spinner-border text-primary mb-2" role="status">
    <span class="visually-hidden">Cargando...</span>
  </div>
  <p class="text-muted small mb-0">Cargando datos...</p>
</div>

<!-- Skeleton screens -->
<div class="placeholder-glow">
  <div class="row g-2">
    <% 5.times do |i| %>
      <div class="col-12">
        <div class="d-flex align-items-center gap-3 py-2">
          <div class="placeholder rounded-circle" style="width:32px;height:32px;"></div>
          <div class="flex-grow-1">
            <div class="placeholder col-8 mb-1"></div>
            <div class="placeholder col-4"></div>
          </div>
        </div>
      </div>
    <% end %>
  </div>
</div>
```

**B. Transiciones suaves:**

```scss
.card {
  transition: transform 0.2s ease, box-shadow 0.2s ease;

  &:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(0,0,0,0.08);
  }
}

.nav-link {
  transition: all 0.2s ease;
}

.badge {
  transition: background-color 0.2s ease;
}
```

---

### 8. RESPONSIVE DESIGN

#### Mejoras Mobile-First

```erb
<!-- Stack vertical en mobile, horizontal en desktop -->
<div class="row g-3 g-lg-4">
  <div class="col-12 col-md-6 col-xl-4">
    <!-- KPI card -->
  </div>
</div>

<!-- Ocultar elementos secundarios en mobile -->
<div class="d-none d-md-block">
  <span class="text-muted">vs LY: <%= ly %></span>
</div>

<!-- Tabs responsivos: dropdown en mobile, tabs en desktop -->
<ul class="nav nav-tabs d-none d-md-flex">
  <!-- Desktop tabs -->
</ul>
<select class="form-select d-md-none">
  <!-- Mobile dropdown -->
</select>
```

---

## 📐 Plantilla de Implementación

### Paso 1: Crear partials mejorados

**`app/views/admin/dashboard/_kpi_hero.html.erb`:**
```erb
<div class="card bg-white border-0 shadow-sm <%= border_variant(title) %> h-100">
  <div class="card-body p-4">
    <div class="label-hero text-muted mb-2">
      <i class="<%= icon_for(title) %> me-1"></i>
      <%= title %>
    </div>
    <div class="hero-value text-dark mb-2">
      <%= number_to_currency(value, precision: 0, delimiter: ',') %>
    </div>
    <div class="d-flex align-items-center gap-2 flex-wrap">
      <% if delta %>
        <span class="badge <%= delta_badge_class(delta) %> px-2 py-1">
          <i class="fa <%= delta >= 0 ? 'fa-arrow-up' : 'fa-arrow-down' %> me-1"></i>
          <%= number_to_percentage(delta.abs * 100, precision: 1) %>
        </span>
      <% end %>
      <% if ly %>
        <span class="text-muted small">LY: <%= number_to_currency(ly, precision: 0) %></span>
      <% end %>
    </div>
  </div>
</div>
```

**`app/views/admin/dashboard/_kpi_secondary.html.erb`:**
```erb
<div class="card bg-white border-0 shadow-sm h-100">
  <div class="card-body p-3">
    <div class="label-standard text-muted mb-1">
      <%= title %>
    </div>
    <div class="secondary-value fw-semibold text-dark">
      <%= value %>
    </div>
    <% if subtitle %>
      <div class="small text-muted mt-1"><%= subtitle %></div>
    <% end %>
  </div>
</div>
```

**`app/views/admin/dashboard/_kpi_tactical.html.erb`:**
```erb
<div class="card bg-light border-0 h-100">
  <div class="card-body p-2 px-3">
    <div class="text-muted small mb-0"><%= title %></div>
    <div class="tactical-value fw-semibold"><%= value %></div>
  </div>
</div>
```

### Paso 2: Helper methods

**`app/helpers/dashboard_helper.rb`:**
```ruby
module DashboardHelper
  def border_variant(title)
    case title
    when /Ventas|Revenue/i
      'border-start border-4 border-success'
    when /Ganancia|Profit/i
      'border-start border-4 border-primary'
    when /Margen|Margin/i
      'border-start border-4 border-warning'
    when /Inventario/i
      'border-start border-4 border-info'
    else
      'border-start border-2 border-secondary'
    end
  end

  def delta_badge_class(delta)
    return 'bg-light text-muted border border-secondary' unless delta
    if delta >= 0
      'bg-success-subtle text-success border border-success'
    else
      'bg-danger-subtle text-danger border border-danger'
    end
  end

  def icon_for(title)
    case title
    when /Ventas/i then 'fa-solid fa-chart-line'
    when /Ganancia/i then 'fa-solid fa-money-bill-trend-up'
    when /Margen/i then 'fa-solid fa-percent'
    when /Inventario/i then 'fa-solid fa-boxes-stacked'
    when /Clientes/i then 'fa-solid fa-users'
    else 'fa-solid fa-circle-info'
    end
  end
end
```

### Paso 3: CSS personalizado

**`app/assets/stylesheets/dashboard.scss`:**
```scss
.dashboard {
  // Hero KPIs
  .hero-value {
    font-size: clamp(2rem, 4vw, 2.5rem);
    font-weight: 700;
    line-height: 1.2;
  }

  .secondary-value {
    font-size: clamp(1.5rem, 3vw, 1.75rem);
    font-weight: 600;
    line-height: 1.3;
  }

  .tactical-value {
    font-size: 1.25rem;
    font-weight: 600;
    line-height: 1.4;
  }

  .label-hero {
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .label-standard {
    font-size: 0.8125rem;
    font-weight: 500;
  }

  // Card improvements
  .card {
    transition: transform 0.2s ease, box-shadow 0.2s ease;

    &:hover {
      transform: translateY(-2px);
      box-shadow: 0 0.5rem 1.5rem rgba(0, 0, 0, 0.08) !important;
    }
  }

  // Badges improvements
  .badge {
    font-weight: 600;
    padding: 0.375rem 0.75rem;
    border-radius: 0.375rem;
  }

  // Tables in cards
  .table {
    margin-bottom: 0;

    th {
      font-size: 0.75rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      color: var(--bs-secondary);
      border-bottom-width: 2px;
    }

    td {
      font-size: 0.875rem;
      vertical-align: middle;
    }
  }

  // Nav improvements
  .nav-pills {
    .nav-link {
      font-weight: 500;
      border-radius: 0.5rem;
      transition: all 0.2s ease;

      &.active {
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.12);
      }
    }
  }
}

// Spacing utilities
.pt-section {
  padding-top: 2rem;

  @media (min-width: 768px) {
    padding-top: 3rem;
  }
}

.mb-section {
  margin-bottom: 2rem;

  @media (min-width: 768px) {
    margin-bottom: 3rem;
  }
}
```

---

## 🎨 Esquema de Colores Propuesto

```scss
// Override Bootstrap variables or add custom
$success: #10b981;    // Verde moderno
$primary: #3b82f6;    // Azul vibrante
$warning: #f59e0b;    // Naranja/amarillo
$danger: #ef4444;     // Rojo
$info: #06b6d4;       // Cyan
$secondary: #6b7280;  // Gris neutro

// Subtle variants (10% opacity)
$success-subtle: rgba($success, 0.1);
$primary-subtle: rgba($primary, 0.1);
$warning-subtle: rgba($warning, 0.1);
$danger-subtle: rgba($danger, 0.1);
```

---

## 📱 Breakpoints y Responsividad

```scss
// Mobile-first approach
.dashboard {
  // Default (mobile)
  .hero-value { font-size: 2rem; }

  // Tablet
  @media (min-width: 768px) {
    .hero-value { font-size: 2.25rem; }
  }

  // Desktop
  @media (min-width: 1200px) {
    .hero-value { font-size: 2.5rem; }
  }
}

// Grid adjustments
.row {
  --bs-gutter-x: 1rem;

  @media (min-width: 992px) {
    --bs-gutter-x: 1.5rem;
  }
}
```

---

## ✅ Checklist de Implementación

### Fase 1: Foundation (1-2 días)
- [ ] Crear helpers en `dashboard_helper.rb`
- [ ] Agregar `dashboard.scss` con sistema tipográfico
- [ ] Crear partials: `_kpi_hero`, `_kpi_secondary`, `_kpi_tactical`
- [ ] Actualizar colores y variantes

### Fase 2: Layout (2-3 días)
- [ ] Reorganizar grid principal (hero → secondary → tactical)
- [ ] Mejorar espaciado entre secciones
- [ ] Implementar separadores visuales
- [ ] Ajustar responsive breakpoints

### Fase 3: Components (2-3 días)
- [ ] Refactorizar tabs anidados
- [ ] Mejorar loading states con skeletons
- [ ] Agregar transiciones suaves
- [ ] Optimizar tablas con datos

### Fase 4: Polish (1-2 días)
- [ ] Pruebas mobile/tablet/desktop
- [ ] Ajustar contraste y accesibilidad
- [ ] Validar rendimiento (lazy loading turbo frames)
- [ ] Documentar componentes en Storybook (opcional)

---

## 🔍 Métricas de Éxito

Antes vs Después:
- **Tiempo para encontrar KPI principal**: 5s → 2s
- **Claridad visual (escala 1-10)**: 6 → 9
- **Satisfacción usuario (NPS)**: Medir antes/después
- **Mobile usability**: Mejorar de "difícil" a "excelente"

---

## 📚 Referencias de Diseño

- **Inspiración**: Stripe Dashboard, Linear.app, Notion Analytics
- **Patterns**: [Material Design Dashboards](https://m3.material.io/)
- **Accesibilidad**: WCAG 2.1 AA compliance
- **Performance**: Core Web Vitals targets

---

## 🚀 Quick Wins (Implementación Rápida)

Si solo tienes 2-3 horas:

1. **Agregar border-start a hero KPIs** (5 min)
2. **Cambiar tamaños de fuente** (10 min)
3. **Espaciado: `mb-3` → `mb-4` en secciones principales** (5 min)
4. **Badges para deltas con iconos** (15 min)
5. **Hover effect en cards** (10 min)

Total: ~45 minutos para mejora visible del 40-50%.

---

**Documento creado**: 2025-10-12
**Versión**: 1.0
**Autor**: AI UX Advisor
