# frozen_string_literal: true

module ApplicationHelper
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

  # Preload simplificado para la imagen LCP de home (collection_shelf-960w.*)
  # Genera hasta tres <link rel="preload"> si existen las variantes
  def lcp_preload_home_image
    base = 'collection_shelf-960w'
    tags = []
    {
      'image/avif' => 'avif',
      'image/webp' => 'webp',
      'image/jpeg' => 'jpg'
    }.each do |mime, ext|
      file = "#{base}.#{ext}"
      next unless asset_exists?(file)

      tags << tag.link(rel: 'preload', as: 'image', href: asset_path(file), fetchpriority: 'high', imagesrcset: "#{asset_path(file)} 960w",
                       imagesizes: '(max-width: 960px) 100vw, 960px', type: mime)
    end
    safe_join(tags)
  end

  # Preload LCP para página de producto (usa ActiveStorage). Pre-carga variantes 600x600.
  def lcp_preload_product_image(product)
    return '' unless product.respond_to?(:product_images) && product.product_images.attached?

    attachment = product.product_images.first
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
