# frozen_string_literal: true

class CartItemsController < ApplicationController
  before_action :set_cart

  def create
    @product = Product.find(params[:product_id])
    @condition = params[:condition].presence || 'brand_new'
    @collectible = @condition != 'brand_new'

    unless @product.active?
      respond_to do |format|
        format.turbo_stream { flash.now[:alert] = 'Producto no disponible' }
        format.html { redirect_back fallback_location: catalog_path, alert: 'Producto no disponible' }
        format.json { render json: { error: 'Producto no disponible' }, status: :unprocessable_entity }
      end
      return
    end

    # Validar disponibilidad de inventario por condición
    available_count = available_for_condition(@product, @condition)
    current_in_cart = @cart.quantity_for(@product.id, condition: @condition)
    desired_total = current_in_cart + 1

    # Validar stock disponible
    if desired_total > available_count && !@product.oversell_allowed?
      msg = if @collectible
              'Esta pieza coleccionable ya no está disponible.'
            else
              "Stock insuficiente (disponibles: #{available_count}). Este producto no permite preventa ni sobre pedido."
            end
      respond_to do |format|
        format.turbo_stream { flash.now[:alert] = msg }
        format.html { redirect_back fallback_location: catalog_path, alert: msg }
        format.json { render json: { error: msg }, status: :unprocessable_entity }
      end
      return
    end

    # Validar límites del carrito (3 nuevos, 1 coleccionable) y persistir: para
    # un cliente autenticado la mutación se confirma en la base antes de
    # responder; para un visitante sigue en la sesión.
    outcome = @storefront.add(@product, @condition)
    if outcome == :limit_exceeded
      max = @cart.max_allowed(@condition)
      msg = if @collectible
              'Solo puedes agregar 1 pieza coleccionable de esta condición por producto.'
            else
              "Máximo #{max} unidades nuevas por producto."
            end
      respond_to do |format|
        format.turbo_stream { flash.now[:alert] = msg }
        format.html { redirect_back fallback_location: catalog_path, alert: msg }
        format.json { render json: { error: msg }, status: :unprocessable_entity }
      end
      return
    end

    return render_cart_unavailable(catalog_path) unless outcome == :ok

    @cart = @storefront.cart
    label = @collectible ? "(#{condition_label(@condition)})" : ''
    flash.now[:notice] = "#{@product.product_name} #{label} fue agregado exitosamente" if request.format.turbo_stream?

    respond_to do |format|
      format.turbo_stream { render :create }
      format.html { redirect_to cart_path, notice: "#{@product.product_name} agregado al carrito." }
      format.json do
        render json: {
          total_items: @cart.item_count,
          cart_total: helpers.number_to_currency(@cart.total)
        }
      end
    end
  end

  def update
    @product = Product.find(params[:product_id])
    @condition = params[:condition].presence || 'brand_new'
    @collectible = @condition != 'brand_new'
    @stay_open = params[:stay_open].present?

    unless @product.active?
      respond_to do |format|
        format.turbo_stream { flash.now[:alert] = 'Producto no disponible' }
        format.html { redirect_back fallback_location: cart_path, alert: 'Producto no disponible' }
        format.json { render json: { error: 'Producto no disponible' }, status: :unprocessable_entity }
      end
      return
    end

    desired = params[:quantity].to_i
    available_count = available_for_condition(@product, @condition)
    max_allowed = @cart.max_allowed(@condition)

    # Validar stock
    if desired.positive? && desired > available_count && !@product.oversell_allowed?
      msg = "No puedes agregar #{desired} unidades. Stock disponible: #{available_count}."
      respond_to do |format|
        format.turbo_stream { flash.now[:alert] = msg }
        format.html { redirect_back fallback_location: cart_path, alert: msg }
        format.json { render json: { error: msg }, status: :unprocessable_entity }
      end
      return
    end

    # Validar límite del carrito y persistir la cantidad exacta
    outcome = @storefront.set_quantity(@product, @condition, desired)
    if outcome == :limit_exceeded
      msg = @collectible ? 'Máximo 1 pieza coleccionable.' : "Máximo #{max_allowed} unidades."
      respond_to do |format|
        format.turbo_stream { flash.now[:alert] = msg }
        format.html { redirect_back fallback_location: cart_path, alert: msg }
        format.json { render json: { error: msg }, status: :unprocessable_entity }
      end
      return
    end

    return render_cart_unavailable(cart_path) unless outcome == :ok

    @cart = @storefront.cart

    respond_to do |format|
      format.turbo_stream { render :update }
      format.html { redirect_to cart_path }
      format.json do
        qty = @cart.quantity_for(@product.id, condition: @condition)
        item_price = price_for_condition(@product, @condition)
        line_total_plain = helpers.number_to_currency(item_price * qty)
        pending_totals = @cart.pending_summary
        item_split = @product.split_immediate_and_pending(qty, condition: @condition)

        render json: {
          product_id: @product.id,
          condition: @condition,
          quantity: qty,
          line_total: line_total_plain,
          cart_total: helpers.number_to_currency(@cart.total),
          subtotal: helpers.number_to_currency(@cart.subtotal),
          tax_amount: helpers.number_to_currency(@cart.tax_amount),
          subtotal_with_tax: helpers.number_to_currency(@cart.subtotal + @cart.tax_amount),
          tax_enabled: @cart.tax_enabled?,
          total_items: @cart.item_count,
          item_immediate: item_split[:immediate].to_i,
          item_in_transit: item_split[:in_transit_qty].to_i,
          item_pending: item_split[:pending].to_i,
          item_pending_type: item_split[:pending_type]&.to_s,
          max_allowed: max_allowed,
          can_increase: qty < max_allowed && (qty < available_count || @product.oversell_allowed?),
          summary_pending_total: pending_totals[:pending_total],
          summary_in_transit_total: pending_totals[:in_transit_total],
          summary_preorder_total: pending_totals[:preorder_total],
          summary_backorder_total: pending_totals[:backorder_total]
        }
      end
    end
  end

  def destroy
    @product = Product.find(params[:product_id])
    @condition = params[:condition].presence
    @stay_open = params[:stay_open].present?

    return render_cart_unavailable(cart_path) unless @storefront.remove(@product, condition: @condition) == :ok

    @cart = @storefront.cart

    respond_to do |format|
      format.turbo_stream do
        if request.referer&.include?('/cart')
          render :remove_row
        else
          render :destroy
        end
      end
      format.html { redirect_to cart_path }
      format.json do
        pending_totals = @cart.pending_summary
        render json: {
          cart_total: helpers.number_to_currency(@cart.total),
          subtotal: helpers.number_to_currency(@cart.subtotal),
          tax_amount: helpers.number_to_currency(@cart.tax_amount),
          subtotal_with_tax: helpers.number_to_currency(@cart.subtotal + @cart.tax_amount),
          tax_enabled: @cart.tax_enabled?,
          total_items: @cart.item_count,
          summary_pending_total: pending_totals[:pending_total],
          summary_in_transit_total: pending_totals[:in_transit_total],
          summary_preorder_total: pending_totals[:preorder_total],
          summary_backorder_total: pending_totals[:backorder_total]
        }
      end
    end
  end

  private

  def set_cart
    @storefront = storefront_cart
    @cart = @storefront.cart
  end

  # La mutación durable no pudo confirmarse (p. ej. carrera agotada): nunca se
  # reporta éxito ni se toca sólo la sesión; el estado persistente sigue
  # siendo el canónico y el cliente puede reintentar.
  def render_cart_unavailable(fallback)
    msg = 'No pudimos actualizar tu carrito. Intenta de nuevo.'
    respond_to do |format|
      format.turbo_stream { flash.now[:alert] = msg }
      format.html { redirect_back fallback_location: fallback, alert: msg }
      format.json { render json: { error: msg }, status: :unprocessable_entity }
    end
  end

  def available_for_condition(product, condition)
    # Sólo piezas vendibles: :available CON ubicación física o :in_transit
    # (ya comprado, en camino). Espejo de Product#publishable_stock? para no
    # permitir ordenar piezas que el admin no puede localizar.
    product.sellable_inventory.where(item_condition: condition).count
  end

  def price_for_condition(product, condition)
    product.customer_price_for_condition(condition)
  end

  def condition_label(condition)
    case condition.to_s
    when 'brand_new' then 'Nuevo'
    when 'misb' then 'MISB'
    when 'moc' then 'MOC'
    when 'mib' then 'MIB'
    when 'mint' then 'Mint'
    when 'loose' then 'Loose'
    when 'good' then 'Good'
    when 'fair' then 'Fair'
    else condition.to_s.titleize
    end
  end
end
