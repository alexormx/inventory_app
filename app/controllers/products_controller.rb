# frozen_string_literal: true

class ProductsController < ApplicationController
  layout 'customer'
  # Catálogo y detalle públicos (precio y carrito solo para autenticados)
  before_action :set_product, only: :show
  before_action :ensure_public_product_active, only: :show
  skip_before_action :track_visitor, only: :recently_viewed

  PUBLIC_PER_PAGE = 24
  MAX_RECENTLY_VIEWED_PRODUCTS = 10
  MAX_RECENTLY_VIEWED_CANDIDATES = 50
  RECENTLY_VIEWED_SLUG_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  # SEO-friendly brand landing page: /marca/:brand_slug
  def brand
    @brand_name = find_brand_by_slug(params[:brand_slug])
    unless @brand_name
      redirect_to catalog_path, alert: 'Marca no encontrada'
      return
    end

    params[:brands] = [@brand_name]
    @seo_landing = :brand
    index
    render :index
  end

  # SEO-friendly category landing page: /categoria/:category_slug
  def category
    @category_name = find_category_by_slug(params[:category_slug])
    unless @category_name
      redirect_to catalog_path, alert: 'Categoría no encontrada'
      return
    end

    params[:categories] = [@category_name]
    @seo_landing = :category
    index
    render :index
  end

  # SEO-friendly series landing page: /serie/:series_slug
  def series
    @series_name = find_series_by_slug(params[:series_slug])
    unless @series_name
      redirect_to catalog_path, alert: 'Serie no encontrada'
      return
    end

    params[:series] = [@series_name]
    @seo_landing = :series
    index
    render :index
  end

  # Aggregated landing for the whole Tomica line (every series matching
  # "Tomica%"). Targets the "Tomica México" query class that none of
  # the individual series pages cover by themselves.
  def tomica_hub
    @hub_name = 'Tomica'
    @seo_landing = :tomica_hub
    @series_prefix = 'Tomica'
    index
    render :index
  end

  def index
    catalog_query = CatalogQuery.new(params)
    @q = catalog_query.q
    @sort = catalog_query.sort

    # Universe scope — narrowed when called from a hub landing that
    # only deals with a series prefix (e.g. /tomica → "Tomica%").
    universe = Product.publicly_visible
    universe = universe.where('series ILIKE ?', "#{@series_prefix}%") if @series_prefix.present?

    # Facetas básicas para filtros (ordenar en Ruby para evitar DISTINCT + ORDER BY en PG)
    @all_categories = universe.distinct.pluck(:category).compact.compact_blank.sort_by { |c| c.to_s.downcase }
    @all_brands     = universe.distinct.pluck(:brand).compact.compact_blank.sort_by { |b| b.to_s.downcase }
    @all_series     = universe.distinct.pluck(:series).compact.compact_blank.sort_by { |s| s.to_s.downcase }

    # Calcular rango de precios para el slider
    price_stats = universe.pick(Arel.sql('MIN(selling_price) as min_price, MAX(selling_price) as max_price'))
    @price_range_min = (price_stats&.first || 0).to_f.floor
    @price_range_max = (price_stats&.last || 10_000).to_f.ceil

    # Base scope (aplicar búsqueda primero para contadores precisos).
    # search_catalog combina substring + similitud de trigramas (tolera typos).
    base_scope = universe
    base_scope = base_scope.search_catalog(@q) if @q.present?

    filters = catalog_query.filters

    # Contadores de facetas conscientes de filtros: cada dimensión cuenta con
    # todos los demás filtros aplicados (excepto el suyo propio), para que las
    # opciones reflejen lo que pasaría al seleccionarlas sin romper el
    # multi-select dentro de la misma dimensión.
    @facet_counts = calculate_facet_counts(base_scope, filters)

    # Aplicar filtros
    scope = apply_catalog_filters(base_scope, filters)

    scope = case @sort
            when 'price_asc'  then scope.order(selling_price: :asc)
            when 'price_desc' then scope.order(selling_price: :desc)
            when 'name_asc'   then scope.order(Arel.sql('LOWER(product_name) ASC'))
            when 'popular'
              # Productos con más unidades vendidas históricas
              scope.left_joins(:sale_order_items)
                   .group('products.id')
                   .order(Arel.sql('COALESCE(SUM(sale_order_items.quantity), 0) DESC, products.created_at DESC'))
            when 'reviews_desc'
              # Mejor calificados: avg rating de reseñas aprobadas, luego volumen.
              # Subquery (no LEFT JOIN) para evitar el problema de filtrar
              # filas pendientes/rechazadas al agregar — productos sin
              # reseñas aprobadas reciben COALESCE 0 y van al final.
              approved = Review.statuses[:approved].to_i
              scope.order(Arel.sql(<<~SQL))
                (SELECT COALESCE(AVG(rating), 0) FROM reviews
                  WHERE product_id = products.id AND status = #{approved}) DESC,
                (SELECT COUNT(*) FROM reviews
                  WHERE product_id = products.id AND status = #{approved}) DESC,
                products.created_at DESC
              SQL
            else # newest (determinista) — o relevancia si hay búsqueda activa
              if @q.present? && (relevance = Product.search_relevance_order(@q))
                scope.order(relevance).order(created_at: :desc, id: :desc)
              else
                scope.order(created_at: :desc, id: :desc)
              end
            end

    # Preload de imágenes para evitar N+1 de ActiveStorage en la grilla
    @products = scope.with_attached_product_images.page(catalog_query.page).per(PUBLIC_PER_PAGE)
    # Precalcular on_hand counts en batch para evitar N+1 (simple hash)
    product_ids = @products.map(&:id)
    @on_hand_counts = Inventory.customer_on_hand.where(product_id: product_ids)
                               .group(:product_id).count
    @in_transit_counts = Inventory.customer_in_transit.where(product_id: product_ids).group(:product_id).count
    # Precalcular agregados de reseñas aprobadas para mostrar estrellas
    # en cada card sin N+1.
    approved_reviews = Review.approved.where(product_id: product_ids)
    @review_counts = approved_reviews.group(:product_id).count
    @review_averages = approved_reviews.group(:product_id).average(:rating)
                                       .transform_values { |v| v.to_f.round(1) }
    # Para productos sin stock pero con piezas en tránsito, calcular la fecha
    # más próxima de llegada (de la PO con expected_delivery_date más temprana).
    products_without_stock = product_ids - @on_hand_counts.keys
    @in_transit_etas = if products_without_stock.any?
                         Inventory.customer_in_transit.where(product_id: products_without_stock)
                                  .joins(:purchase_order)
                                  .where.not(purchase_orders: { expected_delivery_date: nil })
                                  .where('purchase_orders.expected_delivery_date >= ?', Date.current)
                                  .group(:product_id)
                                  .minimum('purchase_orders.expected_delivery_date')
                       else
                         {}
                       end
    # Top 4 categorías por número de productos para sugerir en el empty state
    @top_categories = Product.publicly_visible.where.not(category: [nil, ''])
                             .group(:category).order(Arel.sql('COUNT(*) DESC'))
                             .limit(4).pluck(:category)
  end

  def show
    # @product ya cargado y validado por before_action
    # Productos relacionados: misma categoría o marca, excluyendo el actual
    @related_products = Product.publicly_visible
                               .where.not(id: @product.id)
                               .where('category = ? OR brand = ?', @product.category, @product.brand)
                               .with_attached_product_images
                               .order(Arel.sql('RANDOM()'))
                               .limit(4)

    # Precalcular stock para productos relacionados
    related_ids = @related_products.map(&:id)
    @related_on_hand = Inventory.customer_on_hand.where(product_id: related_ids)
                                .group(:product_id).count
  end

  # Resolves the visitor's compact, client-side slug history against current
  # public product state. Presentation data deliberately never comes from
  # localStorage, so renamed/repriced products and replaced images self-heal.
  def recently_viewed
    requested_slugs = recently_viewed_slugs
    products_by_slug = Product.publicly_visible
                              .includes(product_images_attachments: :blob)
                              .where(slug: requested_slugs)
                              .index_by(&:slug)
    @recently_viewed_products = requested_slugs.filter_map { |slug| products_by_slug[slug] }
                                               .first(MAX_RECENTLY_VIEWED_PRODUCTS)

    render partial: 'recently_viewed_cards',
           locals: { products: @recently_viewed_products },
           layout: false
  end

  private

  def recently_viewed_slugs
    return [] unless params[:slugs].is_a?(Array)

    params[:slugs]
      .first(MAX_RECENTLY_VIEWED_CANDIDATES)
      .filter_map do |slug|
        next unless slug.is_a?(String)

        normalized = slug.strip.downcase
        normalized if normalized.length <= 255 && normalized.match?(RECENTLY_VIEWED_SLUG_PATTERN)
      end
      .uniq
  end

  # Aplica los filtros del catálogo a un scope. `except:` omite una dimensión
  # (usado por los contadores de facetas para no auto-filtrarse).
  def apply_catalog_filters(scope, f, except: nil)
    scope = scope.where(category: f[:categories]) if except != :categories && f[:categories].present?
    scope = scope.where(brand: f[:brands])        if except != :brands && f[:brands].present?
    scope = scope.where(series: f[:series])       if except != :series && f[:series].present?

    unless except == :price
      scope = scope.where(selling_price: f[:price_min].to_f..) if f[:price_min].present?
      scope = scope.where(selling_price: ..f[:price_max].to_f) if f[:price_max].present?
    end

    scope = scope.with_condition_groups(f[:conditions]) if except != :conditions && f[:conditions].any?

    unless except == :availability
      # Grupo de disponibilidad — los 3 chips combinan con OR cuando hay 1+ activos.
      availability_scopes = []
      availability_scopes << Product.with_customer_on_hand if f[:in_stock]
      availability_scopes << Product.with_customer_in_transit if f[:in_transit]
      availability_scopes << Product.where(backorder_allowed: true).or(Product.where(preorder_available: true)) if f[:to_order]

      if availability_scopes.any?
        combined_availability = availability_scopes.reduce { |combined, candidate| combined.or(candidate) }
        scope = scope.merge(combined_availability)
      end

    end

    scope
  end

  def calculate_facet_counts(base_scope, filters)
    cat_scope    = apply_catalog_filters(base_scope, filters, except: :categories)
    brand_scope  = apply_catalog_filters(base_scope, filters, except: :brands)
    series_scope = apply_catalog_filters(base_scope, filters, except: :series)
    cond_scope   = apply_catalog_filters(base_scope, filters, except: :conditions)
    avail_scope  = apply_catalog_filters(base_scope, filters, except: :availability)

    condition_counts = Product::CONDITION_GROUPS.transform_values do |item_conditions|
      cond_scope.where(id: Inventory.customer_on_hand
                                    .where(item_condition: item_conditions)
                                    .select(:product_id)).count
    end

    {
      categories: cat_scope.where.not(category: [nil, '']).group(:category).count,
      brands: brand_scope.where.not(brand: [nil, '']).group(:brand).count,
      series: series_scope.where.not(series: [nil, '']).group(:series).count,
      in_stock: avail_scope.merge(Product.with_customer_on_hand).count,
      in_transit: avail_scope.merge(Product.with_customer_in_transit).count,
      to_order: avail_scope.where('products.backorder_allowed = ? OR products.preorder_available = ?', true, true).count,
      conditions: condition_counts
    }
  end

  def set_product
    @product = Product.friendly.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to catalog_path, alert: 'Producto no encontrado'
  end

  def ensure_public_product_active
    return if @product&.active?

    msg = if @product&.draft?
            'Este producto está en borrador'
          else
            'Este producto se encuentra inactivo'
          end
    respond_to do |format|
      format.html { redirect_to catalog_path, alert: msg }
      format.json { head :not_found }
    end
  end

  # --- SEO slug helpers ---

  def to_seo_slug(name)
    name.to_s.parameterize
  end

  def find_brand_by_slug(slug)
    Product.publicly_visible
           .distinct.pluck(:brand).compact.compact_blank
           .find { |b| b.parameterize == slug }
  end

  def find_category_by_slug(slug)
    Product.publicly_visible
           .distinct.pluck(:category).compact.compact_blank
           .find { |c| c.parameterize == slug }
  end

  def find_series_by_slug(slug)
    Product.publicly_visible
           .distinct.pluck(:series).compact.compact_blank
           .find { |s| s.parameterize == slug }
  end
end
