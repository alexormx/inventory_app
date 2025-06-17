class CartItemsController < ApplicationController
    before_action :set_cart

  def create
    product = Product.find(params[:product_id])
    @cart.add_product(product.id)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to cart_path, notice: "#{product.product_name} agregado al carrito." }
      format.json do
        render json: {
          total_items: session[:cart].values.sum,
          cart_total: helpers.number_to_currency(@cart.total)
        }
      end
    end
  end

  def update
    product = Product.find(params[:product_id])
    @cart.update(product.id, params[:quantity])
    respond_to do |format|
      format.html { redirect_to cart_path }
      format.json do
        qty = session[:cart][product.id.to_s]
        render json: {
          quantity: qty,
          line_total: helpers.number_to_currency(product.selling_price * qty),
          cart_total: helpers.number_to_currency(@cart.total),
          total_items: session[:cart].values.sum
        }
      end
    end
  end

  def destroy
    product = Product.find(params[:product_id])
    @cart.remove(product.id)
    respond_to do |format|
      format.html { redirect_to cart_path }
      format.json do
        render json: {
          cart_total: helpers.number_to_currency(@cart.total),
          total_items: session[:cart].values.sum
        }
      end
    end
  end

  private

  def set_cart
    @cart = Cart.new(session)
  end

end
