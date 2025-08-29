class CartItemsController < ApplicationController
    before_action :set_cart

  def create
    @product = Product.find(params[:product_id])
    previous_qty = session[:cart][@product.id.to_s]
    @new_row = previous_qty.nil?
    unless @product.active?
      respond_to do |format|
        format.turbo_stream { flash.now[:alert] = "Producto no disponible" }
        format.html { redirect_back fallback_location: catalog_path, alert: "Producto no disponible" }
        format.json { render json: { error: "Producto no disponible" }, status: :unprocessable_entity }
      end
      return
    end
    # Validar stock si no permite oversell
    desired_total = (previous_qty || 0).to_i + 1
    if !@product.oversell_allowed? && desired_total > @product.current_on_hand
      respond_to do |format|
        msg = "Stock insuficiente (disponibles: #{@product.current_on_hand}). Este producto no permite preventa ni sobre pedido."
        format.turbo_stream { flash.now[:alert] = msg }
        format.html { redirect_back fallback_location: catalog_path, alert: msg }
        format.json { render json: { error: msg }, status: :unprocessable_entity }
      end
      return
    end

    @cart.add_product(@product.id)
    flash.now[:notice] = "#{@product.product_name} fue agregado exitosamente" if request.format.turbo_stream?
    respond_to do |format|
      format.turbo_stream do
        if request.referer&.include?("/cart")
          render :create_row
        else
          render :create
        end
      end
      format.html { redirect_to cart_path, notice: "#{@product.product_name} agregado al carrito." }
      format.json do
        render json: {
          total_items: session[:cart].values.sum,
          cart_total: helpers.number_to_currency(@cart.total)
        }
      end
    end
  end

  def update
    @product = Product.find(params[:product_id])
    @stay_open = params[:stay_open].present?
    unless @product.active?
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = "Producto no disponible"
        end
        format.html { redirect_back fallback_location: cart_path, alert: "Producto no disponible" }
        format.json { render json: { error: "Producto no disponible" }, status: :unprocessable_entity }
      end
      return
    end
    desired = params[:quantity].to_i
    if desired > 0 && !@product.oversell_allowed? && desired > @product.current_on_hand
      respond_to do |format|
        msg = "No puedes agregar #{desired} unidades. Stock disponible: #{@product.current_on_hand}. Este producto no permite preventa ni sobre pedido."
        format.turbo_stream { flash.now[:alert] = msg }
        format.html { redirect_back fallback_location: cart_path, alert: msg }
        format.json { render json: { error: msg }, status: :unprocessable_entity }
      end
      return
    end
    @cart.update(@product.id, desired)
    respond_to do |format|
      format.turbo_stream do
        # Determinar si la solicitud viene desde la página de carrito (referer contiene /cart)
        if request.referer&.include?("/cart")
          render :update_row
        else
          render :update
        end
      end
      format.html { redirect_to cart_path }
      format.json do
        qty = session[:cart][@product.id.to_s]
        split = @product.split_immediate_and_pending(qty)
        pending_totals = aggregate_pending
        preorder_position = nil
        if split[:pending_type] == :preorder && split[:pending].positive?
          existing = PreorderReservation.where(product: @product, user: current_user, status: :pending).order(:reserved_at).first
          preorder_position = existing&.position
        end
        line_total_plain = helpers.number_to_currency(@product.selling_price * qty)
        render json: {
          product_id: @product.id,
          quantity: qty,
          line_total: line_total_plain,
          cart_total: helpers.number_to_currency(@cart.total),
          subtotal: helpers.number_to_currency(@cart.subtotal),
          tax_amount: helpers.number_to_currency(@cart.tax_amount),
          shipping_cost: helpers.number_to_currency(@cart.shipping_cost),
          grand_total: helpers.number_to_currency(@cart.grand_total),
          tax_enabled: @cart.tax_enabled?,
          total_items: session[:cart].values.sum,
          item_immediate: split[:immediate],
          item_pending: split[:pending],
          item_pending_type: split[:pending_type],
          item_preorder_position: preorder_position,
          summary_pending_total: pending_totals[:pending_total],
          summary_preorder_total: pending_totals[:preorder_total],
          summary_backorder_total: pending_totals[:backorder_total]
        }
      end
    end
  end

  def destroy
    @product = Product.find(params[:product_id])
    @stay_open = params[:stay_open].present?
    @cart.remove(@product.id)
    respond_to do |format|
      format.turbo_stream do
        if request.referer&.include?("/cart")
          render :remove_row
        else
          render :destroy
        end
      end
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

  def aggregate_pending
    pending_total = 0; preorder_total = 0; backorder_total = 0
    @cart.items.each do |product, qty|
      s = product.split_immediate_and_pending(qty)
      pending_total += s[:pending]
      preorder_total += (s[:pending_type] == :preorder ? s[:pending] : 0)
      backorder_total += (s[:pending_type] == :backorder ? s[:pending] : 0)
    end
    { pending_total: pending_total, preorder_total: preorder_total, backorder_total: backorder_total }
  end

end
