# frozen_string_literal: true

module CatalogHelper
  # Genera breadcrumbs dinámicos para el catálogo
  def catalog_breadcrumbs
    breadcrumbs = [
      { name: "Inicio", url: root_path },
      { name: "Catálogo", url: catalog_path }
    ]

    # Agregar filtros activos a breadcrumbs
    if params[:q].present?
      breadcrumbs << { name: "Búsqueda: #{params[:q]}", url: nil }
    end

    if params[:categories].present?
      Array(params[:categories]).reject(&:blank?).each do |cat|
        breadcrumbs << { name: cat, url: nil }
      end
    end

    breadcrumbs
  end

  # Genera breadcrumbs para la vista de producto individual
  def product_breadcrumbs(product)
    [
      { name: "Inicio", url: root_path },
      { name: "Catálogo", url: catalog_path },
      { name: product.category, url: catalog_path(categories: [product.category]) },
      { name: product.product_name, url: nil }
    ]
  end

  # Formato de rango de productos mostrados (ej: "Mostrando 1-12 de 45")
  def products_range_text(products)
    return "No hay productos" if products.total_count.zero?

    from = ((products.current_page - 1) * products.limit_value) + 1
    to = [from + products.limit_value - 1, products.total_count].min

    content_tag(:span, class: "text-muted small") do
      concat "Mostrando "
      concat content_tag(:strong, "#{from}-#{to}", class: "text-dark")
      concat " de "
      concat content_tag(:strong, products.total_count, class: "text-dark")
      concat " productos"
    end
  end

  # Badge para indicar número de filtros activos
  def active_filters_count
    count = 0
    count += Array(params[:categories]).reject(&:blank?).size
    count += Array(params[:brands]).reject(&:blank?).size
    count += 1 if params[:price_min].present? || params[:price_max].present?
    count += 1 if ActiveModel::Type::Boolean.new.cast(params[:in_stock])
    count += 1 if ActiveModel::Type::Boolean.new.cast(params[:backorder])
    count += 1 if ActiveModel::Type::Boolean.new.cast(params[:preorder])
    count
  end
end
