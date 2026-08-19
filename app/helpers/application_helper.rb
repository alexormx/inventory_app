# frozen_string_literal: true

module ApplicationHelper
  include MetaTagsHelper

  # Un flash llega con la clave que usó el controlador (:notice, :alert,
  # :success, :warning, :error...). Todo lo visual y de accesibilidad se deriva
  # de una única severidad normalizada, para que color, icono, urgencia y
  # auto-cierre no puedan contradecirse entre sí.
  FLASH_SEVERITIES = {
    'notice' => :success,
    'success' => :success,
    'alert' => :error,
    'error' => :error,
    'danger' => :error,
    'warning' => :warning
  }.freeze

  FLASH_ALERT_CLASSES = {
    success: 'alert-success', warning: 'alert-warning',
    error: 'alert-danger', info: 'alert-info'
  }.freeze

  FLASH_ICONS = {
    success: 'fa-circle-check', warning: 'fa-triangle-exclamation',
    error: 'fa-circle-exclamation', info: 'fa-circle-info'
  }.freeze

  def flash_severity(flash_type)
    FLASH_SEVERITIES.fetch(flash_type.to_s, :info)
  end

  def flash_alert_class(severity)
    FLASH_ALERT_CLASSES.fetch(severity, 'alert-info')
  end

  def flash_icon(severity)
    FLASH_ICONS.fetch(severity, 'fa-circle-info')
  end

  # Sólo lo que interrumpe se anuncia como interrupción. Un "guardado" no debe
  # cortar al lector de pantalla a mitad de frase.
  def flash_aria_role(severity)
    severity.in?(%i[error warning]) ? 'alert' : 'status'
  end

  def flash_aria_live(severity)
    severity.in?(%i[error warning]) ? 'assertive' : 'polite'
  end

  # 0 = no se cierra solo. Los errores y avisos esperan a que el usuario los
  # cierre; lo informativo se va solo.
  def flash_auto_dismiss_ms(severity)
    severity.in?(%i[error warning]) ? 0 : 3000
  end

  # Se conserva porque otras vistas siguen llamándolo.
  def bootstrap_class_for(flash_type)
    flash_alert_class(flash_severity(flash_type))
  end

  def currency_symbol_for(code)
    {
      'MXN' => '$',
      'USD' => '$',
      'EUR' => '€',
      'JPY' => '¥',
      'GBP' => '£',
      'CNY' => '¥',
      'KRW' => '₩'
    }[code] || code
  end

  def language_switcher_enabled?
    SiteSetting.get('language_switcher_enabled', false) && I18n.available_locales.size > 1
  end

  def dark_mode_enabled?
    SiteSetting.get('dark_mode_enabled', false)
  end

  def user_initials(user)
    return '?' unless user.respond_to?(:name) && user.name.present?

    parts = user.name.split
    (parts.first[0] + (parts.size > 1 ? parts.last[0] : '')).upcase
  end

  # Comprueba si un asset precompilado o en pipeline existe (no lanza excepciones)
  def asset_exists?(logical_path)
    Rails.application.assets&.find_asset(logical_path) || (
    Rails.application.config.assets.compile == false &&
    Rails.application.assets_manifest&.assets&.key?(logical_path)
  )
  rescue StandardError
    false
  end

  # Google Analytics 4 snippet. Emits gtag.js async + config call when
  # SiteSetting('google_analytics_id') is set (e.g., 'G-XXXXXXXXXX').
  # Only included by the customer layout — admin pages are intentionally
  # not tracked. ID is validated to avoid HTML injection from settings.
  def google_analytics_snippet
    id = SiteSetting.get('google_analytics_id').to_s.strip
    return ''.html_safe if id.blank?
    return ''.html_safe unless id.match?(/\A[A-Z]+-[A-Z0-9-]{4,}\z/i)

    src = "https://www.googletagmanager.com/gtag/js?id=#{j(id)}"
    # gtag() calls queue into dataLayer immediately; the gtag.js library is
    # loaded lazily on first interaction, or after load+idle as a fallback so
    # bounced sessions are still counted. This keeps the ~150KB third-party
    # script off the critical path (lower TBT) without losing tracking.
    config = <<~JS
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', '#{j(id)}', { anonymize_ip: true });
      (function(){
        if (window.__gaDeferredInit) return; window.__gaDeferredInit = true;
        var loaded = false, opts = { passive: true, once: true };
        var events = ['scroll','mousemove','touchstart','keydown','click'];
        function loadGA(){
          if (loaded) return; loaded = true;
          events.forEach(function(ev){ window.removeEventListener(ev, loadGA, opts); });
          var s = document.createElement('script');
          s.src = '#{src}'; s.async = true;
          document.head.appendChild(s);
        }
        events.forEach(function(ev){ window.addEventListener(ev, loadGA, opts); });
        function armFallback(){ setTimeout(loadGA, 3000); }
        if (document.readyState === 'complete') armFallback();
        else window.addEventListener('load', armFallback, { once: true });
      })();
    JS

    tag.script(config.html_safe)
  end

  # Preload de la imagen LCP del home (hero). Usa el patrón responsive
  # preload (imagesrcset + imagesizes) para que el browser elija el ancho
  # correcto según el viewport — móvil descarga ~50KB, escritorio ~325KB,
  # en lugar de un único 2.5MB. Prefiere AVIF cuando existen variantes
  # responsive, luego WebP, y skip si no hay nada.
  def lcp_preload_home_image
    base = 'collection_shelf'
    widths = [480, 768, 960, 1440]

    %w[avif webp].each do |ext|
      mime = ext == 'avif' ? 'image/avif' : 'image/webp'
      next unless widths.all? { |w| asset_exists?("#{base}-#{w}w.#{ext}") }

      srcset = widths.map { |w| "#{asset_path("#{base}-#{w}w.#{ext}")} #{w}w" }.join(', ')
      return tag.link(rel: 'preload', as: 'image',
                      imagesrcset: srcset,
                      imagesizes: '100vw',
                      type: mime,
                      fetchpriority: 'high')
    end

    ''.html_safe
  end

  # Preload LCP para página de producto (usa ActiveStorage). Pre-carga variantes 600x600.
  def lcp_preload_product_image(product)
    return '' unless product.respond_to?(:product_images) && product.product_images.attached?

    attachment = product.primary_product_image
    tags = []
    {
      'image/avif' => :avif,
      'image/webp' => :webp,
      'image/jpeg' => nil
    }.each do |mime, fmt|
      variant_opts = { resize_to_limit: [600, 600] }
      variant_opts[:format] = fmt if fmt
      url = url_for(attachment.variant(**variant_opts))
      if I18n.locale && I18n.locale != I18n.default_locale
        url = url.sub(%r{/#{I18n.locale}/rails/active_storage}, '/rails/active_storage')
        if url.include?('locale=')
          begin
            uri = URI.parse(url)
            params = URI.decode_www_form(uri.query).except('locale')
            uri.query = params.empty? ? nil : URI.encode_www_form(params)
            url = uri.to_s
          rescue StandardError; end
        end
      end
      tags << tag.link(rel: 'preload', as: 'image', href: url, fetchpriority: 'high', type: mime)
    rescue StandardError => e
      Rails.logger.debug { "[lcp_preload_product_image] fallo variante #{mime}: #{e.message}" }
    end
    safe_join(tags)
  end

  # Returns a URL only when it uses a safe http(s) scheme, otherwise nil.
  # Use for hrefs built from externally-sourced data (e.g. supplier-provided
  # source_url) so a `javascript:`/`data:` value can never become a live link.
  def safe_external_url(url)
    str = url.to_s.strip
    return if str.blank?

    uri = URI.parse(str)
    str if uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    nil
  end

  # Helper para contar items del carrito desde la sesión
  # Maneja el nuevo formato {product_id => {condition => qty}}
  def cart_item_count
    Cart.new(session).item_count
  end
end
