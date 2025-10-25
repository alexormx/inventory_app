class HomeController < ApplicationController
  layout "customer"

  def index
    # Show 8 featured products (active, with stock, newest first)
    @products = Product.active
                      .where("stock_quantity > ?", 0)
                      .order(created_at: :desc)
                      .limit(8)
  end
end
