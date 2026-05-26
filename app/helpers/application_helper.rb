# frozen_string_literal: true

module ApplicationHelper
  include MetaTagsHelper

  def bootstrap_class_for(flash_type)
    case flash_type.to_sym
    when :notice then 'alert-success'
    when :alert then 'alert-danger'
    when :error then 'alert-danger'
    when :warning then 'alert-warning'
    else 'alert-info'
    end
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

    src = "https://www.googletagmanager.com/gtag/js?id=#{ERB::Util.html_escape(id)}"
    config = <<~JS
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', '#{j(id)}', { anonymize_ip: true });
    JS

    safe_join([
                tag.script(src: src, async: true),
                tag.script(config.html_safe)
              ])
  end

  # Preload de la imagen LCP del home (hero). Usa el patrón responsive
  # preload (imagesrcset + imagesizes) para que el browser elija el ancho
  # correcto según el viewport — móvil descarga ~50KB, escritorio ~325KB,
  # en lugar de un único 2.5MB. Prefiere AVIF cuando existen variantes
  # responsive, luego WebP, y skip si no hay nada.
  def lcp_preload_home_image
    base = 'collection_shelf'
    widths = [480, 960, 1440]

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

  # Helper para contar items del carrito desde la sesión
  # Maneja el nuevo formato {product_id => {condition => qty}}
  def cart_item_count
    cart_data = session[:cart]
    return 0 if cart_data.blank?

    cart_data.values.sum do |conditions|
      if conditions.is_a?(Hash)
        conditions.values.sum.to_i
      else
        conditions.to_i # Formato legacy: {product_id => qty}
      end
    end
  end
end
