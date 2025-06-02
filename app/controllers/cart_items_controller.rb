class CartItemsController < ApplicationController
    def create
    product = Product.find(params[:product_id])
    cart = session[:cart] ||= {}

    cart[product.id.to_s] ||= 0
    cart[product.id.to_s] += 1

    session[:cart] = cart
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to products_path, notice: "#{product.product_name} agregado al carrito." }
    end
  end
end
