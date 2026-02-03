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
  #   - price_min: Precio mínimo (String o nil)
  #   - price_max: Precio máximo (String o nil)
  #   - in_stock_only: Boolean - filtrar solo productos en stock
  #   - backorder_only: Boolean - filtrar solo productos con backorder
  #   - preorder_only: Boolean - filtrar solo productos en preventa
  #   - has_filters: Boolean - si hay al menos un filtro activo
  def filter_state
    @filter_state ||= build_filter_state
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

  # URL para limpiar todos los filtros (mantiene sort y q)
  def clear_all_filters_url
    catalog_path(sort: @sort, q: @q)
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

  # Normaliza request.query_parameters para evitar llaves duplicadas del tipo
  # categories vs categories[] y brands vs brands[].
  # También quita paginación para que al limpiar filtros se regrese a la primera página.
  def normalized_catalog_query_parameters
    qp = request.query_parameters.deep_dup
    qp.delete('page')

    cats = Array(qp.delete('categories')) + Array(qp.delete('categories[]'))
    cats = cats.compact_blank.uniq
    qp['categories'] = cats if cats.present?

    brands = Array(qp.delete('brands')) + Array(qp.delete('brands[]'))
    brands = brands.compact_blank.uniq
    qp['brands'] = brands if brands.present?

    qp
  end

  def build_filter_state
    OpenStruct.new(
      selected_categories: (Array(params[:categories]) + Array(params['categories[]'])).compact_blank.uniq,
      selected_brands: (Array(params[:brands]) + Array(params['brands[]'])).compact_blank.uniq,
      price_min: params[:price_min].presence,
      price_max: params[:price_max].presence,
      in_stock_only: boolean_param(:in_stock),
      backorder_only: boolean_param(:backorder),
      preorder_only: boolean_param(:preorder)
    ).tap do |state|
      state.has_filters = state.selected_categories.any? ||
                          state.selected_brands.any? ||
                          state.price_min.present? ||
                          state.price_max.present? ||
                          state.in_stock_only ||
                          state.backorder_only ||
                          state.preorder_only
    end
  end

  def boolean_param(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
  end
end
