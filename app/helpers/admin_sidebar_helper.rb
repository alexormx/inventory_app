# frozen_string_literal: true

# Helper aislado para los enlaces de la barra lateral de administración.
# Mantener separado de `ApplicationHelper` reduce fricción con RuboCop en código legacy.
module AdminSidebarHelper
  SIDEBAR_ICON_STYLE_PREFIXES = %w[fa fa-solid fa-regular fa-brands fas far fab].freeze

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

    icon_html = content_tag(:i, '', class: "fa-solid #{normalize_sidebar_icon(icon)} me-2 sidebar-link-icon", aria: { hidden: true })

    link_to path, class: classes.join(' '), aria: aria, title: label do
      safe_join([icon_html, content_tag(:span, label, class: 'sidebar-label sidebar-link-label')])
    end
  end

  private

  def normalize_sidebar_icon(icon)
    tokens = icon.to_s.strip.split.reject(&:blank?)
    icon_token = tokens.find do |token|
      token.start_with?('fa-') && !SIDEBAR_ICON_STYLE_PREFIXES.include?(token)
    end

    icon_token ||= tokens.find { |token| !SIDEBAR_ICON_STYLE_PREFIXES.include?(token) }
    icon_token = 'circle' if icon_token.blank?

    icon_token.start_with?('fa-') ? icon_token : "fa-#{icon_token}"
  end
end
