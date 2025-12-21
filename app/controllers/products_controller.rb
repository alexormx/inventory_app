# frozen_string_literal: true

class ProductsController < ApplicationController
  layout 'customer'
  # Requiere sesión para ver catálogo y productos
  before_action :authenticate_user!
  before_action :set_product, only: :show
  before_action :ensure_public_product_active, only: :show

  PUBLIC_PER_PAGE = 15
  def index
    @q      = params[:q].to_s.strip
    @sort   = params[:sort].presence || 'newest'

    # Facetas básicas para filtros (ordenar en Ruby para evitar DISTINCT + ORDER BY en PG)
    @all_categories = Product.publicly_visible.distinct.pluck(:category).compact.compact_blank.sort_by { |c| c.to_s.downcase }
    @all_brands     = Product.publicly_visible.distinct.pluck(:brand).compact.compact_blank.sort_by { |b| b.to_s.downcase }

    # Calcular rango de precios para el slider
    price_stats = Product.publicly_visible.pick(Arel.sql('MIN(selling_price) as min_price, MAX(selling_price) as max_price'))
    @price_range_min = (price_stats&.first || 0).to_f.floor
    @price_range_max = (price_stats&.last || 10_000).to_f.ceil

    # Base scope (aplicar búsqueda primero para contadores precisos)
    base_scope = Product.publicly_visible
    if @q.present?
      pattern = "%#{@q.downcase}%"
      base_scope = base_scope.where('LOWER(product_name) LIKE ? OR LOWER(category) LIKE ? OR LOWER(brand) LIKE ?', pattern, pattern, pattern)
    end

    # Calcular contadores de facetas para el scope base
    @facet_counts = calculate_facet_counts(base_scope)

    # Aplicar filtros
    scope = base_scope
    selected_categories = Array(params[:categories]).compact_blank
    selected_brands     = Array(params[:brands]).compact_blank
    price_min           = params[:price_min].presence
    price_max           = params[:price_max].presence
    in_stock_only       = ActiveModel::Type::Boolean.new.cast(params[:in_stock])
    backorder_only      = ActiveModel::Type::Boolean.new.cast(params[:backorder])
    preorder_only       = ActiveModel::Type::Boolean.new.cast(params[:preorder])

    scope = scope.where(category: selected_categories) if selected_categories.present?
    scope = scope.where(brand: selected_brands) if selected_brands.present?
    scope = scope.where(selling_price: price_min.to_f..) if price_min.present?
    scope = scope.where(selling_price: ..price_max.to_f) if price_max.present?
    scope = scope.joins(:inventories).where(inventories: { status: Inventory.statuses[:available] }).distinct if in_stock_only
    scope = scope.where(backorder_allowed: true) if backorder_only
    scope = scope.where(preorder_available: true) if preorder_only

    scope = case @sort
            when 'price_asc'  then scope.order(selling_price: :asc)
            when 'price_desc' then scope.order(selling_price: :desc)
            when 'name_asc'   then scope.order(Arel.sql('LOWER(product_name) ASC'))
            else # newest (deterministic)
              scope.order(created_at: :desc, id: :desc)
            end

    # Preload de imágenes para evitar N+1 de ActiveStorage en la grilla
    @products = scope.with_attached_product_images.page(params[:page]).per(PUBLIC_PER_PAGE)
    # Precalcular on_hand counts en batch para evitar N+1 (simple hash)
    product_ids = @products.map(&:id)
    @on_hand_counts = Inventory.where(product_id: product_ids, status: :available)
                               .group(:product_id).count
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
    @related_on_hand = Inventory.where(product_id: related_ids, status: :available)
                                .group(:product_id).count
  end

  private

  def calculate_facet_counts(scope)
    {
      categories: scope.where.not(category: [nil, '']).group(:category).count,
      brands: scope.where.not(brand: [nil, '']).group(:brand).count,
      in_stock: scope.joins(:inventories).where(inventories: { status: Inventory.statuses[:available] }).distinct.count,
      backorder: scope.where(backorder_allowed: true).count,
      preorder: scope.where(preorder_available: true).count
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
end
