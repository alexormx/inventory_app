# frozen_string_literal: true

# Helper aislado para los enlaces de la barra lateral de administración.
# Mantener separado de `ApplicationHelper` reduce fricción con RuboCop en código legacy.
module AdminSidebarHelper
  # Genera un enlace de la barra lateral con lógica de estado activo controlada.
  # Parámetros:
  #   label  - Texto visible.
  #   path   - Ruta de destino.
  #   icon:  - Clase FontAwesome (puede incluir el prefijo fa- o solo el nombre).
  #   section: - true => activo cuando la ruta es raíz o un sub‑path (prefijo con '/');
  #             false => coincidencia exacta.
  def admin_sidebar_link(label, path, icon:, section: false)
    current = request.path.chomp('/')
    target  = path.chomp('/')

    # Lógica de coincidencia: prioriza exact, luego sección; caso por defecto ya cubre exact.
    active = if section
               current == target || current.start_with?("#{target}/")
             else
               current == target
             end

    classes = %w[nav-link text-white d-flex align-items-center]
    classes << 'active' if active
    aria = active ? { current: 'page' } : {}

    icon_class = icon.start_with?('fa-') ? icon : "fa-#{icon}"
    icon_html = content_tag(:i, '', class: "fa #{icon_class} me-2")

    link_to path, class: classes.join(' '), aria: aria do
      safe_join([icon_html, content_tag(:span, label, class: 'sidebar-label')])
    end
  end
end
