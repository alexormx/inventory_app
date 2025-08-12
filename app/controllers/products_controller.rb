class ProductsController < ApplicationController
  layout "customer"
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
  end
end
