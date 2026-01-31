# frozen_string_literal: true

module SeoHelper
  # Genera JSON-LD structured data para un producto (Schema.org Product)
  def product_json_ld(product)
    return unless product

    on_hand = product.current_on_hand rescue 0
    availability = if on_hand > 0
                     'https://schema.org/InStock'
                   elsif product.backorder_allowed?
                     'https://schema.org/BackOrder'
                   elsif product.preorder_available?
                     'https://schema.org/PreOrder'
                   else
                     'https://schema.org/OutOfStock'
                   end

    image_url = if product.product_images.attached?
                  url_for(product.product_images.first)
                else
                  asset_url('placeholder.png')
                end

    data = {
      '@context' => 'https://schema.org',
      '@type' => 'Product',
      'name' => product.product_name,
      'sku' => product.product_sku,
      'description' => product.description.presence || "#{product.product_name} - #{product.brand} #{product.category}",
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
          'name' => 'Pasatiempos a Escala'
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

    tag.script(data.to_json.html_safe, type: 'application/ld+json')
  end

  # Genera JSON-LD BreadcrumbList para SEO
  def breadcrumb_json_ld(breadcrumbs)
    return unless breadcrumbs.present?

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
    data = {
      '@context' => 'https://schema.org',
      '@type' => 'Organization',
      'name' => 'Pasatiempos a Escala',
      'url' => root_url,
      'logo' => asset_url('logo.png'),
      'description' => 'Tienda especializada en modelos a escala, autos de colección y figuras. Productos originales de las mejores marcas.',
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

    tag.script(data.to_json.html_safe, type: 'application/ld+json')
  end

  # Genera JSON-LD ItemList para páginas de catálogo
  def product_list_json_ld(products)
    return unless products.present?

    items = products.each_with_index.map do |product, index|
      image_url = if product.product_images.attached?
                    url_for(product.product_images.first)
                  else
                    asset_url('placeholder.png')
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

  # Meta tags para producto
  def product_meta_title(product)
    "#{product.product_name} | #{product.brand} | Pasatiempos a Escala"
  end

  def product_meta_description(product)
    base = product.description.presence || "#{product.product_name} de #{product.brand}"
    # Limitar a ~155 caracteres para SEO
    truncated = base.truncate(155, separator: ' ')
    "#{truncated} Compra en Pasatiempos a Escala. Envío seguro. Producto 100% original."
  end

  # Meta tags para catálogo
  def catalog_meta_title
    parts = ['Catálogo']
    parts << params[:categories].join(', ') if params[:categories].present?
    parts << params[:brands].join(', ') if params[:brands].present?
    parts << '| Pasatiempos a Escala'
    parts.join(' ')
  end

  def catalog_meta_description
    desc = 'Explora nuestra colección de modelos a escala, autos de colección y figuras.'
    if params[:categories].present?
      desc += " Categorías: #{params[:categories].join(', ')}."
    end
    if params[:brands].present?
      desc += " Marcas: #{params[:brands].join(', ')}."
    end
    desc + ' Productos originales con envío seguro a todo México.'
  end

  # Canonical URL helper
  def canonical_url
    # Para páginas de catálogo, remover parámetros de paginación del canonical
    if controller_name == 'products' && action_name == 'index'
      catalog_url(request.query_parameters.except('page'))
    else
      request.original_url.split('?').first
    end
  end
end
