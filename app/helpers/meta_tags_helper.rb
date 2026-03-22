# frozen_string_literal: true

module MetaTagsHelper
  DEFAULT_SITE_NAME = 'Pasatiempos a Escala'
  DEFAULT_SITE_TITLE = 'Tienda de Coleccionables y Autos a Escala'
  DEFAULT_META_DESCRIPTION = 'Tienda especializada en modelos a escala, autos de colección Hot Wheels, Greenlight, Majorette y más. Productos 100% originales con envío a todo México.'
  DEFAULT_KEYWORDS = 'autos a escala, hot wheels, greenlight, coleccionables, tienda de coleccionables, autos de colección, diecast, modelos a escala'
  NOINDEX_CONTROLLERS = %w[carts checkouts profiles orders shipping_addresses].freeze
  INDEXABLE_CATALOG_FILTERS = %w[categories brands series].freeze

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

  def meta_robots_content
    if content_for?(:meta_robots)
      strip_tags(content_for(:meta_robots).to_s).squish
    elsif noindex_catalog_request?
      'noindex, follow'
    elsif noindex_request?
      'noindex, nofollow'
    else
      'index, follow'
    end
  end

  def meta_keywords
    if content_for?(:meta_keywords)
      strip_tags(content_for(:meta_keywords).to_s).squish
    else
      seo_settings[:keywords].presence || DEFAULT_KEYWORDS
    end
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

    # Brand/category landing pages use their own clean URL as canonical
    if @seo_landing == :brand && @brand_name.present?
      return brand_landing_url(brand_slug: @brand_name.parameterize)
    elsif @seo_landing == :category && @category_name.present?
      return category_landing_url(category_slug: @category_name.parameterize)
    elsif @seo_landing == :series && @series_name.present?
      return series_landing_url(series_slug: @series_name.parameterize)
    end

    return catalog_canonical_url if request.path == catalog_path

    explicit.presence || (request.base_url.to_s + request.path.to_s)
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

  private

  def noindex_request?
    controller_path.start_with?('devise/') || NOINDEX_CONTROLLERS.include?(controller_path)
  end

  def noindex_catalog_request?
    return false unless request.path == catalog_path

    query_keys = request.query_parameters.stringify_keys.keys - ['locale']
    query_keys.present? && (query_keys - INDEXABLE_CATALOG_FILTERS).any?
  end

  def catalog_canonical_url
    filters = canonical_catalog_filters
    filters.present? ? catalog_url(filters) : catalog_root_url
  end

  def canonical_catalog_filters
    categories = Array(request.query_parameters[:categories]).map(&:to_s).map(&:strip).reject(&:blank?).uniq.sort
    brands = Array(request.query_parameters[:brands]).map(&:to_s).map(&:strip).reject(&:blank?).uniq.sort
    series = Array(request.query_parameters[:series]).map(&:to_s).map(&:strip).reject(&:blank?).uniq.sort

    {}.tap do |filters|
      filters[:categories] = categories if categories.present?
      filters[:brands] = brands if brands.present?
      filters[:series] = series if series.present?
    end
  end
end
