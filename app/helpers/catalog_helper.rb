# frozen_string_literal: true

module CatalogHelper
  # Genera título dinámico basado en filtros activos
  def catalog_dynamic_title
    parts = []

    return 'Tomica México' if @seo_landing == :tomica_hub

    return "Resultados para \"#{catalog_query.q}\"" if catalog_query.q.present?

    categories = filter_state.selected_categories
    brands = filter_state.selected_brands
    series = filter_state.selected_series

    parts << categories.to_sentence if categories.any?
    parts << brands.to_sentence if brands.any?
    parts << series.to_sentence if series.any?

    parts << 'En Stock' if filter_state.in_stock_only
    parts << 'En tránsito' if filter_state.in_transit_only
    parts << 'Sobre pedido' if filter_state.to_order_only

    parts.any? ? parts.join(' - ') : 'Catálogo de Autos a Escala y Coleccionables en México'
  end

  # Subtítulo contextual
  def catalog_subtitle
    if catalog_query.q.present?
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
    elsif @seo_landing == :tomica_hub
      breadcrumbs << { name: 'Tomica', url: nil }
      return breadcrumbs
    end

    # Agregar filtros activos a breadcrumbs
    breadcrumbs << { name: "Búsqueda: #{catalog_query.q}", url: nil } if catalog_query.q.present?

    if filter_state.selected_categories.present?
      filter_state.selected_categories.each do |cat|
        breadcrumbs << { name: cat, url: nil }
      end
    end

    if filter_state.selected_series.present?
      filter_state.selected_series.each do |series|
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
    filter_state.selected_categories.size +
      filter_state.selected_brands.size +
      filter_state.selected_series.size +
      filter_state.selected_conditions.size +
      (filter_state.price_min.present? || filter_state.price_max.present? ? 1 : 0) +
      [filter_state.in_stock_only, filter_state.in_transit_only, filter_state.to_order_only].count(true)
  end
end
