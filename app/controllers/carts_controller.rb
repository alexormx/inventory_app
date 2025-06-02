class CartsController < ApplicationController
  layout "customer"
  def show
    @cart_items = (session[:cart] || {}).map do |product_id, quantity|
      product = Product.find_by(id: product_id)
      [product, quantity] if product
    end.compact
  end
end
