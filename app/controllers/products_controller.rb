class ProductsController < ApplicationController
  layout "customer"
  # Requiere sesión para ver catálogo y productos
  before_action :authenticate_user!
  def index
    if params[:q].present?
      query = "%#{params[:q].downcase}%"
      @products = Product.publicly_visible
                        .where("LOWER(product_name) LIKE ? OR LOWER(category) LIKE ? OR LOWER(brand) LIKE ?", query, query, query)
                        .order(created_at: :desc)
    else
      @products = Product.publicly_visible.order(created_at: :desc)
    end
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
