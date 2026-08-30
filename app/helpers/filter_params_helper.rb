# frozen_string_literal: true

# Helper para centralizar la lógica de parámetros de filtros del catálogo.
# Evita duplicación en vistas (index.html.erb, _product_grid.html.erb, _filters_form.html.erb).
module FilterParamsHelper
  # Retorna un objeto con el estado actual de todos los filtros.
  # Memoizado para evitar recálculos en la misma request.
  #
  # @return [OpenStruct] con los siguientes atributos:
  #   - selected_categories: Array de categorías seleccionadas
  #   - selected_brands: Array de marcas seleccionadas
  #   - selected_series: Array de series seleccionadas
  #   - price_min: Precio mínimo (String o nil)
  #   - price_max: Precio máximo (String o nil)
  #   - in_stock_only: Boolean - filtrar solo productos en stock
  #   - in_transit_only: Boolean - filtrar productos con inventario en tránsito
  #   - to_order_only: Boolean - filtrar preventa o sobre pedido
  #   - has_filters: Boolean - si hay al menos un filtro activo
  def filter_state
    @filter_state ||= catalog_query.filter_state
  end

  def catalog_query
    @catalog_query ||= CatalogQuery.new(params)
  end

  # URL para limpiar un filtro específico de categoría
  def clear_category_url(category)
    qp = normalized_catalog_query_parameters
    cats = qp.delete('categories')
    new_cats = Array(cats).compact_blank - [category]
    qp['categories'] = new_cats if new_cats.present?
    catalog_path(qp)
  end

  # URL para limpiar un filtro específico de marca
  def clear_brand_url(brand)
    qp = normalized_catalog_query_parameters
    brands = qp.delete('brands')
    new_brands = Array(brands).compact_blank - [brand]
    qp['brands'] = new_brands if new_brands.present?
    catalog_path(qp)
  end

  def clear_series_url(series)
    qp = normalized_catalog_query_parameters
    series_values = qp.delete('series')
    new_series = Array(series_values).compact_blank - [series]
    qp['series'] = new_series if new_series.present?
    catalog_path(qp)
  end

  def clear_condition_url(condition)
    qp = normalized_catalog_query_parameters
    values = qp.delete('conditions')
    new_values = Array(values).compact_blank.map(&:to_s) - [condition.to_s]
    qp['conditions'] = new_values if new_values.present?
    catalog_path(qp)
  end

  # URL para limpiar el filtro de precio
  def clear_price_url
    qp = normalized_catalog_query_parameters
    qp.delete('price_min')
    qp.delete('price_max')
    catalog_path(qp)
  end

  # URL para limpiar un filtro de disponibilidad específico
  def clear_availability_url(filter_key)
    qp = normalized_catalog_query_parameters
    qp.delete(filter_key.to_s)
    catalog_path(qp)
  end

  def enable_availability_url(filter_key)
    qp = normalized_catalog_query_parameters
    qp[filter_key.to_s] = '1'
    catalog_path(qp)
  end

  # Los dos anteriores sólo ponen o quitan una clave del query string, así que
  # sirven igual para dimensiones que no son de disponibilidad. Estos alias
  # existen para que el llamador no tenga que decir "availability" cuando está
  # activando, por ejemplo, "de vuelta recientemente".
  def enable_catalog_flag_url(flag_key)
    enable_availability_url(flag_key)
  end

  def clear_catalog_flag_url(flag_key)
    clear_availability_url(flag_key)
  end

  # URL para limpiar todos los filtros (mantiene sort y q)
  def clear_all_filters_url
    catalog_path(catalog_query.query_parameters.slice('q', 'sort'))
  end

  # URL para limpiar la búsqueda de texto (mantiene filtros y orden)
  def clear_search_url
    qp = normalized_catalog_query_parameters
    qp.delete('q')
    catalog_path(qp)
  end

  # Texto formateado para el chip de precio
  def price_filter_text
    min = filter_state.price_min
    max = filter_state.price_max

    if min && max
      "$#{min} - $#{max}"
    elsif min
      "Desde $#{min}"
    else
      "Hasta $#{max}"
    end
  end

  private

  # Serializa únicamente el contrato público y quita paginación para que una
  # modificación de filtros siempre regrese a la primera página.
  def normalized_catalog_query_parameters
    catalog_query.query_parameters(except: 'page')
  end
end
