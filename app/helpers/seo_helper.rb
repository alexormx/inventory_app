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
                  url_for(product.primary_product_image)
                else
                  asset_url('placeholder.png')
                end

    data = {
      '@context' => 'https://schema.org',
      '@type' => 'Product',
      'name' => product.product_name,
      'sku' => product.product_sku,
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

  # Build a keyword-rich description for JSON-LD Product schema
  def product_json_ld_description(product)
    attrs = product.parsed_custom_attributes
    parts = []

    if product.description.present?
      parts << product.description.to_s.gsub(/\r\n|\n/, ' ').squish.truncate(300, separator: ' ')
    end

    type_label = product_type_label(product)
    parts << "#{product.product_name} de #{product.brand}" if product.brand.present?
    parts << type_label if type_label.present?
    parts << "Escala #{attrs['escala']}" if attrs['escala'].present?
    parts << attrs['material'] if attrs['material'].present?
    parts << "Disponible en #{seo_site_name}"

    parts.compact.reject(&:blank?).join('. ')
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
      item['item'] = crumb[:url] if crumb[:url].present?
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
                    url_for(product.primary_product_image)
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
    data = {
      '@context' => 'https://schema.org',
      '@type' => 'CollectionPage',
      'name' => name,
      'url' => url,
      'description' => if type == :brand
                          "Colección completa de productos #{name} disponibles en #{seo_site_name}."
                        elsif type == :series
                          "Todos los productos de la serie #{name} disponibles en #{seo_site_name}."
                        else
                          "Todos los productos de la categoría #{name} en #{seo_site_name}."
                        end,
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
    attrs = product.parsed_custom_attributes
    scale = attrs['escala'].presence
    material = attrs['material'].presence

    # Build keyword-rich description for Google snippets
    intro = "Compra #{product.product_name} de #{product.brand}"
    intro += " escala #{scale}" if scale.present?
    intro += ", #{material.downcase}" if material.present?
    intro += '.'

    # Add product description snippet if available
    if product.description.present?
      snippet = product.description.to_s.gsub(/\r\n|\n/, ' ').squish.truncate(100, separator: ' ')
      intro += " #{snippet}"
    end

    # Ensure it ends with CTA and store branding
    suffix = " Envío seguro a todo México. 100% original. #{seo_site_name}."
    (intro + suffix).truncate(320, separator: ' ')
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
      parts = ['Catálogo']
      parts << params[:categories].join(', ') if params[:categories].present?
      parts << params[:brands].join(', ') if params[:brands].present?
      parts << params[:series].join(', ') if params[:series].present?
      parts << "| #{seo_site_name}"
      parts.join(' ')
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
