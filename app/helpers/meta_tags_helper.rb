# frozen_string_literal: true

module MetaTagsHelper
  DEFAULT_SITE_NAME = 'Pasatiempos a Escala'
  DEFAULT_ALTERNATE_NAME = 'Pasatiempos'
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

  # Short brand/alternate name surfaced to Google's "site name" feature via the
  # WebSite/Organization JSON-LD alternateName property.
  def brand_alternate_name
    SiteSetting.get('seo_alternate_name', DEFAULT_ALTERNATE_NAME).to_s.presence || DEFAULT_ALTERNATE_NAME
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

  # Canonical home URL with a trailing slash (e.g. "https://pasatiempos.com.mx/"),
  # used as the root entity URL in WebSite/Organization structured data.
  def site_home_url
    "#{site_root_url}/"
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
    elsif @seo_landing == :tomica_hub
      return tomica_hub_url
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
      'alternateName' => brand_alternate_name,
      'url' => site_home_url,
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
      'alternateName' => brand_alternate_name,
      'url' => site_home_url,
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

  # LocalBusiness/Store schema for local Mexico SEO. Only emitted when at least
  # the core address fields are configured via SiteSettings (so we never lie to
  # Google with partial / placeholder data).
  def json_ld_local_business
    street   = SiteSetting.get('business_address_street').to_s.strip
    locality = SiteSetting.get('business_address_locality').to_s.strip
    region   = SiteSetting.get('business_address_region').to_s.strip
    return nil if street.blank? || locality.blank? || region.blank?

    data = {
      '@context' => 'https://schema.org',
      '@type' => 'Store',
      'name' => site_name,
      'url' => site_root_url,
      'image' => asset_url('logo.png'),
      'description' => seo_settings[:meta_description].presence || DEFAULT_META_DESCRIPTION,
      'address' => {
        '@type' => 'PostalAddress',
        'streetAddress' => street,
        'addressLocality' => locality,
        'addressRegion' => region,
        'addressCountry' => 'MX'
      }
    }

    postal = SiteSetting.get('business_address_postal_code').to_s.strip
    data['address']['postalCode'] = postal if postal.present?

    phone = SiteSetting.get('business_phone').to_s.strip
    data['telephone'] = phone if phone.present?

    lat = SiteSetting.get('business_latitude').to_s.strip
    lng = SiteSetting.get('business_longitude').to_s.strip
    if lat.present? && lng.present?
      data['geo'] = {
        '@type' => 'GeoCoordinates',
        'latitude' => lat.to_f,
        'longitude' => lng.to_f
      }
    end

    hours = SiteSetting.get('business_opening_hours')
    if hours.is_a?(Array) && hours.any?
      data['openingHoursSpecification'] = hours
    end

    area = SiteSetting.get('business_area_served', 'México').to_s.strip
    data['areaServed'] = { '@type' => 'Country', 'name' => area } if area.present?

    price_range = SiteSetting.get('business_price_range').to_s.strip
    data['priceRange'] = price_range if price_range.present?

    data
  end

  def google_site_verification_token
    SiteSetting.get('google_site_verification').to_s.strip.presence
  end

  def hreflang_links
    href = meta_canonical_url
    safe_join([
                tag.link(rel: 'alternate', hreflang: 'es-MX', href: href),
                tag.link(rel: 'alternate', hreflang: 'x-default', href: href)
              ])
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
