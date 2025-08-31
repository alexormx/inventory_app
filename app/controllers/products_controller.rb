class ProductsController < ApplicationController
  layout "customer"
  # Requiere sesión para ver catálogo y productos
  before_action :authenticate_user!

  PUBLIC_PER_PAGE = 15
  def index
    @q      = params[:q].to_s.strip
    @sort   = params[:sort].presence || "newest"

    scope = Product.publicly_visible
    if @q.present?
      pattern = "%#{@q.downcase}%"
      scope = scope.where("LOWER(product_name) LIKE ? OR LOWER(category) LIKE ? OR LOWER(brand) LIKE ?", pattern, pattern, pattern)
    end

    scope = case @sort
    when "price_asc"  then scope.order(selling_price: :asc)
    when "price_desc" then scope.order(selling_price: :desc)
    when "name_asc"   then scope.order(Arel.sql("LOWER(product_name) ASC"))
    else # newest
      scope.order(created_at: :desc)
    end

  # Preload de imágenes para evitar N+1 de ActiveStorage en la grilla
  @products = scope.with_attached_product_images.page(params[:page]).per(PUBLIC_PER_PAGE)
  # Precalcular on_hand counts en batch para evitar N+1 (simple hash)
  product_ids = @products.map(&:id)
  @on_hand_counts = Inventory.where(product_id: product_ids, status: :available)
                 .group(:product_id).count
  end

  def show
    @product = Product.friendly.find(params[:id])
    # Solo permitir ver productos activos para usuarios normales.
    # Admin puede ver cualquiera (aunque normalmente usaría el namespace admin).
    unless current_user&.admin? || @product.active?
      redirect_to catalog_path, alert: "Producto no disponible" and return
    end
  end
end
