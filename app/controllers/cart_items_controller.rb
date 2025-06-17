class CartItemsController < ApplicationController
    before_action :set_cart

  def create
    product = Product.find(params[:product_id])
    @cart.add_product(product.id)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to cart_path, notice: "#{product.product_name} agregado al carrito." }
    end
  end

  def update
    product = Product.find(params[:product_id])
    @cart.update(product.id, params[:quantity])
    respond_to do |format|
      format.turbo_stream { head :ok }
      format.html { redirect_to cart_path }
    end
  end

  def destroy
    product = Product.find(params[:product_id])
    @cart.remove(product.id)
    redirect_to cart_path
  end

  private

  def set_cart
    @cart = Cart.new(session)
  end

end
