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
  #   section: - true => conserva el contexto visual en subrutas, sin afirmar
  #             que el enlace padre sea la página actual.
  def admin_sidebar_link(label, path, icon:, section: false)
    current = normalize_sidebar_path(request.path)
    target = normalize_sidebar_path(path)
    current_page = current == target
    section_active = section && !current_page && current.start_with?("#{target}/")

    classes = %w[nav-link text-white d-flex align-items-center]
    classes << 'active' if current_page
    classes << 'section-active' if section_active
    aria = { label: label }
    aria[:current] = 'page' if current_page

    icon_html = content_tag(:i, '', class: "fa-solid #{normalize_sidebar_icon(icon)} me-2 sidebar-link-icon", aria: { hidden: true })

    link_to path, class: classes.join(' '), aria: aria, title: label do
      safe_join([icon_html, content_tag(:span, label, class: 'sidebar-label sidebar-link-label')])
    end
  end

  private

  def normalize_sidebar_path(path)
    normalized = path.to_s.split('?', 2).first.to_s.chomp('/')
    normalized.presence || '/'
  end

  def normalize_sidebar_icon(icon)
    tokens = icon.to_s.strip.split.compact_blank
    icon_token = tokens.find do |token|
      token.start_with?('fa-') && SIDEBAR_ICON_STYLE_PREFIXES.exclude?(token)
    end

    icon_token ||= tokens.find { |token| SIDEBAR_ICON_STYLE_PREFIXES.exclude?(token) }
    icon_token = 'circle' if icon_token.blank?

    icon_token.start_with?('fa-') ? icon_token : "fa-#{icon_token}"
  end
end
