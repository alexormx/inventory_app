# frozen_string_literal: true

module MetaTagsHelper
  DEFAULT_SITE_NAME = 'Pasatiempos a Escala'
  DEFAULT_SITE_TITLE = 'Tienda de Coleccionables y Autos a Escala'
  DEFAULT_META_DESCRIPTION = 'Tienda especializada en modelos a escala, autos de colección Hot Wheels, Greenlight, Majorette y más. Productos 100% originales con envío a todo México.'
  DEFAULT_KEYWORDS = 'autos a escala, hot wheels, greenlight, coleccionables, tienda de coleccionables, autos de colección, diecast, modelos a escala'

  def seo_settings
    {
      site_name: SiteSetting.get('seo_site_name', DEFAULT_SITE_NAME).to_s,
      site_title: SiteSetting.get('seo_site_title', DEFAULT_SITE_TITLE).to_s,
      meta_description: SiteSetting.get('seo_meta_description', DEFAULT_META_DESCRIPTION).to_s,
      keywords: SiteSetting.get('seo_keywords', DEFAULT_KEYWORDS).to_s
    }
  end

  def site_name
    seo_settings[:site_name].presence || DEFAULT_SITE_NAME
  end

  def site_title
    seo_settings[:site_title].presence || DEFAULT_SITE_TITLE
  end

  def meta_description
    if content_for?(:meta_description)
      strip_tags(content_for(:meta_description).to_s).squish
    else
      seo_settings[:meta_description].presence || DEFAULT_META_DESCRIPTION
    end
  end

  def meta_keywords
    seo_settings[:keywords].presence || DEFAULT_KEYWORDS
  end

  def site_root_url
    request.base_url.to_s.sub(%r{/\z}, '')
  end

  def catalog_root_url
    # canonical del catálogo siempre sin params
    site_root_url + catalog_path
  end

  def meta_canonical_url
    explicit = content_for?(:canonical_url) ? content_for(:canonical_url).to_s : nil
    explicit = explicit.split('?').first if explicit.present?

    computed = explicit.presence || (request.base_url.to_s + request.path.to_s)

    # IMPORTANT: canonicalizar páginas filtradas del catálogo a /catalog
    if request.path == catalog_path && request.query_parameters.present?
      catalog_root_url
    else
      computed
    end
  end

  def page_title
    if content_for?(:title)
      base = strip_tags(content_for(:title).to_s).squish

      # Evitar duplicar el site name si el título ya lo trae
      if base.downcase.include?(site_name.downcase)
        base
      else
        "#{base} | #{site_name}"
      end
    else
      "#{site_name} - #{site_title}"
    end
  end

  def og_title
    page_title
  end

  def og_description
    meta_description
  end

  def og_image
    if content_for?(:og_image)
      content_for(:og_image).to_s
    else
      asset_url('logo.png')
    end
  end

  def og_type
    content_for?(:og_type) ? content_for(:og_type).to_s : 'website'
  end

  def json_ld_organization
    {
      '@context' => 'https://schema.org',
      '@type' => 'Organization',
      'name' => site_name,
      'url' => site_root_url,
      'logo' => asset_url('logo.png'),
      'description' => seo_settings[:meta_description].presence || DEFAULT_META_DESCRIPTION,
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
  end

  def json_ld_website
    {
      '@context' => 'https://schema.org',
      '@type' => 'WebSite',
      'name' => site_name,
      'url' => site_root_url,
      'potentialAction' => {
        '@type' => 'SearchAction',
        'target' => {
          '@type' => 'EntryPoint',
          'urlTemplate' => "#{catalog_root_url}?q={search_term_string}"
        },
        'query-input' => 'required name=search_term_string'
      }
    }
  end
end
