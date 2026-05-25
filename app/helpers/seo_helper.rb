# frozen_string_literal: true

module SeoHelper
  # Obtiene el nombre del sitio desde settings
  def seo_site_name
    SiteSetting.get('seo_site_name', 'Pasatiempos a Escala')
  end

  # Genera JSON-LD structured data para un producto (Schema.org Product)
  def product_json_ld(product)
    return unless product

    on_hand = begin
      product.current_on_hand
    rescue StandardError
      0
    end
    availability = if on_hand.positive?
                     'https://schema.org/InStock'
                   elsif product.backorder_allowed?
                     'https://schema.org/BackOrder'
                   elsif product.preorder_available?
                     'https://schema.org/PreOrder'
                   else
                     'https://schema.org/OutOfStock'
                   end

    image_url = if product.product_images.attached?
                  absolute_url(url_for(product.primary_product_image))
                else
                  asset_url('placeholder.png')
                end

    data = {
      '@context' => 'https://schema.org',
      '@type' => 'Product',
      'name' => product.product_name,
      'description' => product_json_ld_description(product),
      'image' => image_url,
      'brand' => {
        '@type' => 'Brand',
        'name' => product.brand
      },
      'category' => product.category,
      'offers' => {
        '@type' => 'Offer',
        'url' => product_url(product),
        'priceCurrency' => 'MXN',
        'price' => product.selling_price.to_f,
        'availability' => availability,
        'seller' => {
          '@type' => 'Organization',
          'name' => seo_site_name
        }
      }
    }

    # Agregar GTIN/barcode si existe
    data['gtin13'] = product.barcode if product.barcode.present?

    # Agregar código WhatsApp como identificador adicional
    data['mpn'] = product.whatsapp_code if product.whatsapp_code.present?

    # Agregar atributos personalizados relevantes
    if product.parsed_custom_attributes.present?
      attrs = product.parsed_custom_attributes
      data['color'] = attrs['color'] if attrs['color'].present?
      data['material'] = attrs['material'] if attrs['material'].present?

      # Escala como additionalProperty
      if attrs['escala'].present?
        data['additionalProperty'] = [{
          '@type' => 'PropertyValue',
          'name' => 'Escala',
          'value' => attrs['escala']
        }]
      end
    end

    # SEO keywords from AI enrichment
    if product.seo_keywords.is_a?(Array) && product.seo_keywords.any?
      data['keywords'] = product.seo_keywords.join(', ')
    end

    tag.script(data.to_json.html_safe, type: 'application/ld+json')
  end

  # Build a clean description for JSON-LD Product schema. Prefers the human
  # description when present (truncated at a sentence boundary so it never
  # ends mid-word with "..."); otherwise builds a clean fallback sentence
  # from product attributes.
  def product_json_ld_description(product)
    if product.description.present?
      cleaned = product.description.to_s.gsub(/\r\n|\n/, ' ').squish
      return clean_sentence_truncate(cleaned, 300)
    end

    seo_fallback_description(product, max: 300)
  end

  # Genera JSON-LD BreadcrumbList para SEO
  def breadcrumb_json_ld(breadcrumbs)
    return if breadcrumbs.blank?

    items = breadcrumbs.each_with_index.map do |crumb, index|
      item = {
        '@type' => 'ListItem',
        'position' => index + 1,
        'name' => crumb[:name]
      }
      item['item'] = absolute_url(crumb[:url]) if crumb[:url].present?
      item
    end

    data = {
      '@context' => 'https://schema.org',
      '@type' => 'BreadcrumbList',
      'itemListElement' => items
    }

    tag.script(data.to_json.html_safe, type: 'application/ld+json')
  end

  # Genera JSON-LD Organization para la página principal
  def organization_json_ld
    site_name = seo_site_name
    site_description = SiteSetting.get('seo_meta_description',
                                       'Tienda especializada en modelos a escala, autos de colección y figuras. Productos originales de las mejores marcas.')

    # Organization schema
    org_data = {
      '@context' => 'https://schema.org',
      '@type' => 'Organization',
      'name' => site_name,
      'url' => root_url,
      'logo' => asset_url('logo.png'),
      'description' => site_description,
      'address' => {
        '@type' => 'PostalAddress',
        'addressCountry' => 'MX'
      },
      'contactPoint' => {
        '@type' => 'ContactPoint',
        'contactType' => 'customer service',
        'availableLanguage' => 'Spanish'
      }
    }

    # WebSite schema con SearchAction para Google Sitelinks Searchbox
    website_data = {
      '@context' => 'https://schema.org',
      '@type' => 'WebSite',
      'name' => site_name,
      'url' => root_url,
      'potentialAction' => {
        '@type' => 'SearchAction',
        'target' => {
          '@type' => 'EntryPoint',
          'urlTemplate' => "#{catalog_url}?q={search_term_string}"
        },
        'query-input' => 'required name=search_term_string'
      }
    }

    safe_join([
                tag.script(org_data.to_json.html_safe, type: 'application/ld+json'),
                tag.script(website_data.to_json.html_safe, type: 'application/ld+json')
              ])
  end

  # Genera JSON-LD ItemList para páginas de catálogo
  def product_list_json_ld(products)
    return if products.blank?

    items = products.each_with_index.map do |product, index|
      image_url = if product.product_images.attached?
                    absolute_url(url_for(product.primary_product_image))
                  else
                    asset_url('placeholder.png')
                  end

      on_hand = begin
        product.current_on_hand
      rescue StandardError
        0
      end
      availability = if on_hand.positive?
                       'https://schema.org/InStock'
                     elsif product.backorder_allowed?
                       'https://schema.org/BackOrder'
                     elsif product.preorder_available?
                       'https://schema.org/PreOrder'
                     else
                       'https://schema.org/OutOfStock'
                     end

      {
        '@type' => 'ListItem',
        'position' => index + 1,
        'item' => {
          '@type' => 'Product',
          'name' => product.product_name,
          'url' => product_url(product),
          'image' => image_url,
          'brand' => {
            '@type' => 'Brand',
            'name' => product.brand
          },
          'offers' => {
            '@type' => 'Offer',
            'url' => product_url(product),
            'priceCurrency' => 'MXN',
            'price' => product.selling_price.to_f,
            'availability' => availability
          }
        }
      }
    end

    data = {
      '@context' => 'https://schema.org',
      '@type' => 'ItemList',
      'itemListElement' => items
    }

    tag.script(data.to_json.html_safe, type: 'application/ld+json')
  end

  # Genera JSON-LD CollectionPage para landing pages de marca/categoría
  def collection_page_json_ld(name:, type:, url:, products: [])
    description = landing_intro(type, name, context: landing_context_for(type, name)).presence ||
                  case type
                  when :brand  then "Colección completa de productos #{name} disponibles en #{seo_site_name}."
                  when :series then "Todos los productos de la serie #{name} disponibles en #{seo_site_name}."
                  else              "Todos los productos de la categoría #{name} en #{seo_site_name}."
                  end

    data = {
      '@context' => 'https://schema.org',
      '@type' => 'CollectionPage',
      'name' => name,
      'url' => url,
      'description' => description,
      'isPartOf' => {
        '@type' => 'WebSite',
        'name' => seo_site_name,
        'url' => root_url
      }
    }

    if products.present?
      data['mainEntity'] = {
        '@type' => 'ItemList',
        'numberOfItems' => products.respond_to?(:total_count) ? products.total_count : products.size,
        'itemListElement' => products.first(20).each_with_index.map do |product, index|
          {
            '@type' => 'ListItem',
            'position' => index + 1,
            'url' => product_url(product),
            'name' => product.product_name
          }
        end
      }
    end

    tag.script(data.to_json.html_safe, type: 'application/ld+json')
  end

  # Meta tags para producto
  def product_meta_title(product)
    attrs = product.parsed_custom_attributes
    scale = attrs['escala'].presence
    # Build keyword-rich title: "Product Name | Brand | Diecast Escala 1:64 | Store"
    parts = [product.product_name, product.brand]
    type_label = product_type_label(product)
    parts << type_label if type_label.present?
    parts << "Escala #{scale}" if scale.present?
    parts << seo_site_name
    parts.join(' | ')
  end

  def product_meta_description(product)
    suffix = " Envío seguro a todo México. 100% original. #{seo_site_name}."
    target_max = 320

    body = if product.description.present?
             cleaned = product.description.to_s.gsub(/\r\n|\n/, ' ').squish
             clean_sentence_truncate(cleaned, target_max - suffix.length)
           else
             seo_fallback_description(product, max: target_max - suffix.length)
           end

    "#{body}#{suffix}"
  end

  # Per-product keywords based on actual product data
  def product_meta_keywords(product)
    # Prefer AI-generated seo_keywords if available
    ai_keywords = product.seo_keywords if product.respond_to?(:seo_keywords)
    if ai_keywords.is_a?(Array) && ai_keywords.any?
      combined = ai_keywords.dup
      # Always include core identifiers
      combined << product.product_name
      combined << product.brand
      combined << product.category
      return combined.compact.map { |k| k.to_s.strip.downcase }.reject(&:blank?).uniq.first(15).join(', ')
    end

    attrs = product.parsed_custom_attributes
    keywords = []

    # Product-specific terms
    keywords << product.product_name
    keywords << product.brand
    keywords << product.category

    # Extract individual words from product name for partial matches
    # e.g. "067 Toyota Hilux" -> "Toyota", "Hilux"
    product.product_name.to_s.split(/\s+/).each do |word|
      keywords << word if word.length > 2 && word != product.brand
    end

    # Type/material keywords
    keywords << 'diecast' if attrs['material'].to_s.downcase.include?('die') || product.category.to_s.downcase.include?('diecast')
    keywords << 'auto a escala' if product_is_diecast?(product)
    keywords << 'modelo a escala' if product_is_diecast?(product)
    keywords << 'coleccionable'
    keywords << attrs['escala'] if attrs['escala'].present?
    keywords << attrs['color'] if attrs['color'].present?

    # Always include core store terms
    keywords += %w[autos\ a\ escala diecast coleccionables modelos\ a\ escala]
    keywords << product.brand.downcase if product.brand.present?

    keywords.compact.map { |k| k.to_s.strip.downcase }.reject(&:blank?).uniq.first(15).join(', ')
  end

  # Returns a unique intro paragraph (plain text) for a brand/category/series
  # landing page. Looks up SiteSetting JSON overrides keyed by slug first; if
  # no override is set, generates a slug-aware fallback that references the
  # landing name, related context, and México — ensuring no two landing pages
  # share identical copy.
  #
  #   type: one of :brand, :category, :series
  #   name: the human name of the landing (e.g. "Takara Tomy")
  #   context: optional hash with extras for richer fallbacks
  #            { related: ['Tomica Premium', 'Tomica Basicos'], product_count: 99 }
  def landing_intro(type, name, context: {})
    return nil if name.blank?

    slug = name.to_s.parameterize
    overrides_key = case type
                    when :brand    then 'seo_intro_brands'
                    when :category then 'seo_intro_categories'
                    when :series   then 'seo_intro_series'
                    end
    return nil unless overrides_key

    overrides = SiteSetting.get(overrides_key) || {}
    overrides = overrides.is_a?(Hash) ? overrides : {}
    override = overrides[slug].to_s.strip
    return override if override.present?

    landing_intro_fallback(type, name, context)
  end

  # Extra OG/product meta tags rendered in <head> on product show.
  # Drives WhatsApp / Facebook share cards (price + stock visible inline).
  def product_og_extensions(product)
    return ''.html_safe unless product

    on_hand = begin
      product.current_on_hand
    rescue StandardError
      0
    end
    availability = if on_hand.positive?
                     'instock'
                   elsif product.backorder_allowed?
                     'backorder'
                   elsif product.preorder_available?
                     'preorder'
                   else
                     'out of stock'
                   end

    tags = [
      tag.meta(property: 'product:price:amount', content: product.selling_price.to_f.to_s),
      tag.meta(property: 'product:price:currency', content: 'MXN'),
      tag.meta(property: 'product:availability', content: availability),
      tag.meta(property: 'product:condition', content: 'new'),
      tag.meta(property: 'og:price:amount', content: product.selling_price.to_f.to_s),
      tag.meta(property: 'og:price:currency', content: 'MXN'),
      tag.meta(property: 'og:availability', content: availability)
    ]

    if product.brand.present?
      tags << tag.meta(property: 'product:brand', content: product.brand)
    end

    safe_join(tags)
  end

  # Ensure a URL is absolute. Accepts paths like "/catalog" and returns
  # "#{request.base_url}/catalog"; passes through already-absolute URLs.
  def absolute_url(url)
    return url if url.blank?
    return url if url.start_with?('http://', 'https://')

    "#{request.base_url}#{url}"
  end

  # SEO-friendly image alt text
  def product_image_alt(product, index: 0)
    attrs = product.parsed_custom_attributes
    alt = product.product_name.to_s.strip
    alt += " #{product.brand}" if product.brand.present?
    type_label = product_type_label(product)
    alt += " #{type_label}" if type_label.present?
    alt += " Escala #{attrs['escala']}" if attrs['escala'].present?
    alt += " - Imagen #{index + 1}" if index > 0
    alt
  end

  private

  # Builds the context hash (related names + product count) used by the
  # fallback templates. Bounded by a single landing's active product set,
  # so it's cheap even on the biggest brand.
  def landing_context_for(type, name)
    return {} if name.blank?

    scope = Product.publicly_visible
    case type
    when :brand
      product_count = scope.where(brand: name).count
      related = scope.where(brand: name).where.not(series: [nil, ''])
                     .group(:series).order(Arel.sql('COUNT(*) DESC')).limit(3).pluck(:series)
      { related: related, product_count: product_count }
    when :category
      product_count = scope.where(category: name).count
      related = scope.where(category: name).where.not(brand: [nil, ''])
                     .group(:brand).order(Arel.sql('COUNT(*) DESC')).limit(3).pluck(:brand)
      { related: related, product_count: product_count }
    when :series
      product_count = scope.where(series: name).count
      related = scope.where(series: name).where.not(brand: [nil, ''])
                     .group(:brand).order(Arel.sql('COUNT(*) DESC')).limit(3).pluck(:brand)
      { related: related, product_count: product_count }
    else
      {}
    end
  end

  # Returns the intro text for the current landing (or nil if not on one).
  # View-friendly wrapper that resolves the right name from instance vars.
  def current_landing_intro
    name = case @seo_landing
           when :brand    then @brand_name
           when :category then @category_name
           when :series   then @series_name
           end
    return nil if @seo_landing.blank? || name.blank?

    landing_intro(@seo_landing, name, context: landing_context_for(@seo_landing, name))
  end

  # Generates a unique intro paragraph when no SiteSetting override exists.
  # Different template per landing type so brand/category/series pages never
  # share identical wording, even before the store provides custom copy.
  def landing_intro_fallback(type, name, context)
    related = Array(context[:related]).reject(&:blank?).first(3)
    count = context[:product_count].to_i

    case type
    when :brand
      lead = "Descubre toda la colección de #{name} disponible en #{seo_site_name}."
      detail = if related.any?
                 " Encuentra modelos originales de las series #{related.to_sentence}, ideales para coleccionistas."
               else
                 " Modelos originales seleccionados para coleccionistas y entusiastas."
               end
      counter = count.positive? ? " Más de #{count} piezas activas en catálogo." : ''
      closer = " 100% productos originales con envío seguro a todo México. Agrega esa pieza única de #{name} a tu colección hoy."
      "#{lead}#{detail}#{counter}#{closer}"

    when :category
      lead = "Explora nuestra selección de #{name} en #{seo_site_name}."
      detail = if related.any?
                 " Trabajamos con marcas como #{related.to_sentence}, todas 100% originales."
               else
                 " Productos originales seleccionados de las mejores marcas del mercado."
               end
      counter = count.positive? ? " Catálogo activo con #{count} productos en #{name}." : ''
      closer = " Envío seguro a todo México y soporte personalizado por WhatsApp para coleccionistas."
      "#{lead}#{detail}#{counter}#{closer}"

    when :series
      lead = "Encuentra todos los productos de la serie #{name} en #{seo_site_name}."
      detail = if related.any?
                 " Esta serie incluye piezas de #{related.to_sentence}, todas originales."
               else
                 " Cada pieza de la serie es original y seleccionada cuidadosamente para coleccionistas."
               end
      counter = count.positive? ? " #{count} productos activos de la serie #{name} en catálogo." : ''
      closer = " Envío seguro a todo México. Completa tu colección de #{name} con piezas auténticas."
      "#{lead}#{detail}#{counter}#{closer}"
    end
  end

  # Truncate text at the last sentence boundary (.!?) before `max`. Falls back
  # to word-boundary truncation if no sentence end is found in the window.
  # Never appends a trailing "...".
  def clean_sentence_truncate(text, max)
    text = text.to_s
    return text if text.length <= max

    window = text[0, max]
    if (last_end = window.rindex(/[.!?]\s/))
      window[0..last_end].strip
    elsif (last_space = window.rindex(' '))
      "#{window[0...last_space].strip}."
    else
      "#{window.strip}."
    end
  end

  # Clean, no-truncation-marks fallback when a product has no description.
  def seo_fallback_description(product, max:)
    attrs = product.parsed_custom_attributes
    scale = attrs['escala'].presence
    material = attrs['material'].presence

    sentence = +"#{product.product_name}"
    sentence << " de #{product.brand}" if product.brand.present?
    type_label = product_type_label(product)
    sentence << " — #{type_label}" if type_label.present?
    sentence << ", escala #{scale}" if scale.present?
    sentence << ", #{material.downcase}" if material.present?
    sentence << '.'

    clean_sentence_truncate(sentence, max)
  end

  # Determine a human-friendly product type label for SEO
  def product_type_label(product)
    attrs = product.parsed_custom_attributes
    material = attrs['material'].to_s.downcase
    category = product.category.to_s.downcase

    if material.include?('die') || category.include?('diecast') || category.include?('basico') || category.include?('premium')
      'Auto a Escala Diecast'
    elsif category.include?('figure') || category.include?('figura')
      'Figura Coleccionable'
    elsif category.include?('toy') || category.include?('juguete')
      'Juguete Coleccionable'
    else
      'Coleccionable'
    end
  end

  # Check if product is a diecast/scale model
  def product_is_diecast?(product)
    attrs = product.parsed_custom_attributes
    material = attrs['material'].to_s.downcase
    category = product.category.to_s.downcase
    brand = product.brand.to_s.downcase

    diecast_brands = %w[tomica hot\ wheels hotwheels greenlight majorette matchbox maisto jada mini\ gt autoworld m2]
    material.include?('die') || category.include?('diecast') || category.include?('basico') || category.include?('premium') ||
      diecast_brands.any? { |b| brand.include?(b) }
  end

  public

  # Meta tags para catálogo
  def catalog_meta_title
    # Landing pages SEO-friendly tienen prioridad
    if @seo_landing == :brand && @brand_name.present?
      "#{@brand_name} | Comprar #{@brand_name} en México | #{seo_site_name}"
    elsif @seo_landing == :category && @category_name.present?
      "#{@category_name} | #{seo_site_name}"
    elsif @seo_landing == :series && @series_name.present?
      "#{@series_name} | #{seo_site_name}"
    else
      filters_active = params[:categories].present? || params[:brands].present? || params[:series].present?
      if filters_active
        parts = ['Catálogo']
        parts << params[:categories].join(', ') if params[:categories].present?
        parts << params[:brands].join(', ') if params[:brands].present?
        parts << params[:series].join(', ') if params[:series].present?
        parts << "| #{seo_site_name}"
        parts.join(' ')
      else
        "Catálogo de Autos a Escala y Coleccionables | Hot Wheels, Tomica, Greenlight en México | #{seo_site_name}"
      end
    end
  end

  def catalog_meta_description
    if @seo_landing == :brand && @brand_name.present?
      "Compra productos #{@brand_name} originales en #{seo_site_name}. " \
        "Amplio catálogo de #{@brand_name} con envío seguro a todo México. " \
        'Modelos a escala, coleccionables y más. 100% originales.'
    elsif @seo_landing == :category && @category_name.present?
      "Explora nuestra selección de #{@category_name} en #{seo_site_name}. " \
        'Productos originales con envío seguro a todo México. Modelos a escala, coleccionables y más.'
    elsif @seo_landing == :series && @series_name.present?
      "Explora la serie #{@series_name} en #{seo_site_name}. " \
        'Productos originales con envío seguro a todo México. Modelos a escala, coleccionables y más.'
    else
      desc = 'Explora nuestra colección de modelos a escala, autos de colección y figuras.'
      desc += " Categorías: #{params[:categories].join(', ')}." if params[:categories].present?
      desc += " Marcas: #{params[:brands].join(', ')}." if params[:brands].present?
      desc += " Series: #{params[:series].join(', ')}." if params[:series].present?
      desc + " Productos originales con envío seguro a todo México. #{seo_site_name}."
    end
  end

  # Canonical URL helper
  def canonical_url
    # Landing pages SEO-friendly usan su propia URL como canonical
    if @seo_landing == :brand && @brand_name.present?
      brand_landing_url(brand_slug: @brand_name.parameterize)
    elsif @seo_landing == :category && @category_name.present?
      category_landing_url(category_slug: @category_name.parameterize)
    elsif @seo_landing == :series && @series_name.present?
      series_landing_url(series_slug: @series_name.parameterize)
    elsif controller_name == 'products' && action_name == 'index'
      catalog_url(request.query_parameters.except('page'))
    else
      request.original_url.split('?').first
    end
  end
end
