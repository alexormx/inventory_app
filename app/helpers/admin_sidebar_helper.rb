# frozen_string_literal: true

# Helper aislado para los enlaces de la barra lateral de administración.
# Mantener separado de `ApplicationHelper` reduce fricción con RuboCop en código legacy.
module AdminSidebarHelper
  SIDEBAR_ICON_STYLE_PREFIXES = %w[fa fa-solid fa-regular fa-brands fas far fab].freeze

  ROLE_LABELS = { 'admin' => 'Administrador', 'customer' => 'Cliente', 'supplier' => 'Proveedor' }.freeze
  BADGE_CACHE_TTL = 2.minutes

  # Genera un enlace de la barra lateral con lógica de estado activo controlada.
  # Parámetros:
  #   label  - Texto visible.
  #   path   - Ruta de destino.
  #   icon:  - Clase FontAwesome (puede incluir el prefijo fa- o solo el nombre).
  #   section: - true => conserva el contexto visual en subrutas, sin afirmar
  #             que el enlace padre sea la página actual.
  #   also:    - rutas secundarias (y sus subrutas) que pertenecen a esta
  #             sección aunque vivan fuera de su prefijo.
  #   badge:   - contador de pendientes; no se muestra si es cero.
  def admin_sidebar_link(label, path, icon:, section: false, also: [], badge: nil)
    current = normalize_sidebar_path(request.path)
    target = normalize_sidebar_path(path)
    current_page = current == target
    section_active = !current_page && (
      (section && current.start_with?("#{target}/")) || also.any? { |p| sidebar_path_covers?(p, current) }
    )

    classes = %w[nav-link text-white d-flex align-items-center]
    classes << 'active' if current_page
    classes << 'section-active' if section_active
    badge = badge.to_i.positive? ? badge.to_i : nil
    aria = { label: badge ? "#{label} (#{badge} pendientes)" : label }
    aria[:current] = 'page' if current_page

    icon_html = content_tag(:i, '', class: "fa-solid #{normalize_sidebar_icon(icon)} me-2 sidebar-link-icon", aria: { hidden: true })
    parts = [icon_html, content_tag(:span, label, class: 'sidebar-label sidebar-link-label')]
    parts << content_tag(:span, badge, class: 'sidebar-badge badge rounded-pill ms-auto', aria: { hidden: true }) if badge

    link_to path, class: classes.join(' '), aria: aria, title: label do
      safe_join(parts)
    end
  end

  # true cuando la página actual está dentro de alguna de las rutas dadas;
  # decide si se despliegan los sub-enlaces de una sección.
  def admin_sidebar_open?(*paths)
    current = normalize_sidebar_path(request.path)
    paths.any? { |p| sidebar_path_covers?(p, current) }
  end

  # Pendientes que muestran contador. Se cachean unos minutos para no sumar
  # consultas a cada página del panel.
  def admin_sidebar_badges
    @admin_sidebar_badges ||= Rails.cache.fetch('admin/sidebar_badges', expires_in: BADGE_CACHE_TTL) do
      {
        order_alerts: SaleOrders::Alerts.counts.values.sum,
        whatsapp: WhatsappRequest.sent.count,
        preorders: PreorderReservation.pending.count,
        reviews: Review.pending.count,
        comments: Comment.pending.count
      }
    end
  end

  def admin_role_label(role)
    ROLE_LABELS.fetch(role.to_s, role.to_s.humanize)
  end

  private

  def sidebar_path_covers?(path, current)
    path = normalize_sidebar_path(path)
    current == path || current.start_with?("#{path}/")
  end

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
