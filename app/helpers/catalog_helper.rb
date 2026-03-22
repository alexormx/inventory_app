# frozen_string_literal: true

module CatalogHelper
  # Genera título dinámico basado en filtros activos
  def catalog_dynamic_title
    parts = []

    return "Resultados para \"#{params[:q]}\"" if params[:q].present?

    categories = Array(params[:categories]).compact_blank
    brands = Array(params[:brands]).compact_blank
    series = Array(params[:series]).compact_blank

    parts << categories.to_sentence if categories.any?
    parts << brands.to_sentence if brands.any?
    parts << series.to_sentence if series.any?

    parts << 'En Stock' if ActiveModel::Type::Boolean.new.cast(params[:in_stock])

    parts << 'Preventa' if ActiveModel::Type::Boolean.new.cast(params[:preorder])

    parts.any? ? parts.join(' - ') : 'Catálogo'
  end

  # Subtítulo contextual
  def catalog_subtitle
    if params[:q].present?
      'Búsqueda en el catálogo'
    elsif active_filters_count.positive?
      "#{active_filters_count} filtro#{'s' if active_filters_count > 1} activo#{'s' if active_filters_count > 1}"
    else
      'Explora nuestra colección completa'
    end
  end

  # Genera breadcrumbs dinámicos para el catálogo
  def catalog_breadcrumbs
    breadcrumbs = [
      { name: 'Inicio', url: root_path },
      { name: 'Catálogo', url: catalog_path }
    ]

    # Landing pages SEO-friendly
    if @seo_landing == :brand && @brand_name.present?
      breadcrumbs << { name: @brand_name, url: nil }
      return breadcrumbs
    elsif @seo_landing == :category && @category_name.present?
      breadcrumbs << { name: @category_name, url: nil }
      return breadcrumbs
    elsif @seo_landing == :series && @series_name.present?
      breadcrumbs << { name: @series_name, url: nil }
      return breadcrumbs
    end

    # Agregar filtros activos a breadcrumbs
    breadcrumbs << { name: "Búsqueda: #{params[:q]}", url: nil } if params[:q].present?

    if params[:categories].present?
      Array(params[:categories]).compact_blank.each do |cat|
        breadcrumbs << { name: cat, url: nil }
      end
    end

    if params[:series].present?
      Array(params[:series]).compact_blank.each do |series|
        breadcrumbs << { name: series, url: nil }
      end
    end

    breadcrumbs
  end

  # Genera breadcrumbs para la vista de producto individual
  def product_breadcrumbs(product)
    crumbs = [
      { name: 'Inicio', url: root_path },
      { name: 'Catálogo', url: catalog_path },
      { name: product.category, url: catalog_path(categories: [product.category]) }
    ]

    # Add brand breadcrumb linking to SEO-friendly brand landing page
    if product.brand.present?
      crumbs << { name: product.brand, url: brand_landing_path(brand_slug: product.brand.parameterize) }
    end

    if (series_name = product_series_name(product))
      crumbs << { name: series_name, url: series_landing_path(series_slug: series_name.parameterize) }
    end

    crumbs << { name: product.product_name, url: nil }
    crumbs
  end

  def product_series_name(product)
    product.series.presence ||
      product.supplier_catalog_item&.canonical_series.presence ||
      product.parsed_custom_attributes['series'].presence ||
      product.parsed_custom_attributes['serie'].presence
  end

  # Formato de rango de productos mostrados (ej: "Mostrando 1-12 de 45")
  def products_range_text(products)
    return 'No hay productos' if products.total_count.zero?

    from = ((products.current_page - 1) * products.limit_value) + 1
    to = [from + products.limit_value - 1, products.total_count].min

    content_tag(:span, class: 'text-muted small') do
      concat 'Mostrando '
      concat content_tag(:strong, "#{from}-#{to}", class: 'text-dark')
      concat ' de '
      concat content_tag(:strong, products.total_count, class: 'text-dark')
      concat ' productos'
    end
  end

  # Badge para indicar número de filtros activos
  def active_filters_count
    count = 0
    count += Array(params[:categories]).compact_blank.size
    count += Array(params[:brands]).compact_blank.size
    count += Array(params[:series]).compact_blank.size
    count += 1 if params[:price_min].present? || params[:price_max].present?
    count += 1 if ActiveModel::Type::Boolean.new.cast(params[:in_stock])
    count += 1 if ActiveModel::Type::Boolean.new.cast(params[:backorder])
    count += 1 if ActiveModel::Type::Boolean.new.cast(params[:preorder])
    count
  end
end
