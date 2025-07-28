class HomeController < ApplicationController
  layout "customer"

  def index
    # puedes pasar
    @products = Product.limit(6)
  end
end
