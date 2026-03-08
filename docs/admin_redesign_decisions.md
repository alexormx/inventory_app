# Decisiones de rediseño del admin

## ADR-001 · Paleta del admin

**Decisión:** adoptar una paleta sobria para el panel administrativo.

**Motivo:** la paleta borgoña anterior cargaba demasiado la navegación y no convivía bien con dashboards, tablas densas y formularios complejos.

**Consecuencia:** el admin usa navegación oscura + contenido claro + acentos discretos. La tienda pública puede seguir otra dirección visual si se desea.

## ADR-002 · Idioma

**Decisión:** normalizar el admin a español.

**Motivo:** la mezcla español/inglés generaba inconsistencia en navegación, breadcrumbs, footer y vistas internas.

**Consecuencia:** los textos nuevos del admin deben escribirse en español. La migración a i18n formal queda como mejora futura si se requiere multilenguaje.

## ADR-003 · Implementación incremental

**Decisión:** rediseñar por capas, empezando por shell + dashboard.

**Motivo:** reduce riesgo, permite validar rápido y evita reescritura total del frontend admin.

**Consecuencia:** formularios, reportes y pantallas de backoffice se irán alineando en iteraciones posteriores, usando los tokens y componentes ya definidos.

## ADR-004 · Estrategia CSS

**Decisión:** favorecer clases semánticas del admin sobre más estilos inline.

**Motivo:** mejora mantenibilidad y cohesión visual.

**Consecuencia:** cualquier mejora futura debe intentar vivir en SCSS y no incrustarse en ERB salvo casos excepcionales.

## ADR-005 · Compatibilidad técnica

**Decisión:** mantener la navegación actual basada en Turbo/Stimulus/JS propio sin reescribir comportamiento por ahora.

**Motivo:** ya existe lógica estable para sidebar y navbar; cambiar la interacción completa en esta fase añade riesgo innecesario.

**Consecuencia:** el rediseño visual no debe romper:
- colapso del sidebar
- menú móvil del navbar
- tabs existentes
- tooltips del dashboard