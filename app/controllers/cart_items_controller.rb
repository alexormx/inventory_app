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

    # Validar límites del carrito (3 nuevos, 1 coleccionable)
    unless @cart.can_add?(@product.id, condition: @condition, quantity: 1)
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

    @cart.add_product(@product.id, 1, condition: @condition)
    label = @collectible ? "(#{condition_label(@condition)})" : ''
    flash.now[:notice] = "#{@product.product_name} #{label} fue agregado exitosamente" if request.format.turbo_stream?

    respond_to do |format|
      format.turbo_stream do
        if request.referer&.include?('/cart')
          render :create_row
        else
          render :create
        end
      end
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

    # Validar límite del carrito
    if desired > max_allowed
      msg = @collectible ? 'Máximo 1 pieza coleccionable.' : "Máximo #{max_allowed} unidades."
      respond_to do |format|
        format.turbo_stream { flash.now[:alert] = msg }
        format.html { redirect_back fallback_location: cart_path, alert: msg }
        format.json { render json: { error: msg }, status: :unprocessable_entity }
      end
      return
    end

    @cart.update(@product.id, desired, condition: @condition)

    respond_to do |format|
      format.turbo_stream do
        if request.referer&.include?('/cart')
          render :update_row
        else
          render :update
        end
      end
      format.html { redirect_to cart_path }
      format.json do
        qty = @cart.quantity_for(@product.id, condition: @condition)
        item_price = price_for_condition(@product, @condition)
        line_total_plain = helpers.number_to_currency(item_price * qty)
        pending_totals = aggregate_pending

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
          summary_pending_total: pending_totals[:pending_total],
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

    @cart.remove(@product.id, condition: @condition)

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
        pending_totals = aggregate_pending
        render json: {
          cart_total: helpers.number_to_currency(@cart.total),
          subtotal: helpers.number_to_currency(@cart.subtotal),
          tax_amount: helpers.number_to_currency(@cart.tax_amount),
          subtotal_with_tax: helpers.number_to_currency(@cart.subtotal + @cart.tax_amount),
          tax_enabled: @cart.tax_enabled?,
          total_items: @cart.item_count,
          summary_pending_total: pending_totals[:pending_total],
          summary_preorder_total: pending_totals[:preorder_total],
          summary_backorder_total: pending_totals[:backorder_total]
        }
      end
    end
  end

  private

  def set_cart
    session[:cart] ||= {}
    @cart = Cart.new(session)
  end

  def available_for_condition(product, condition)
    product.inventories.where(status: :available, item_condition: condition).count
  end

  def price_for_condition(product, condition)
    if condition.to_s == 'brand_new'
      product.selling_price
    else
      avg = product.inventories.where(status: :available, item_condition: condition).average(:selling_price)
      avg&.to_f || product.selling_price
    end
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

  def aggregate_pending
    pending_total = 0
    preorder_total = 0
    backorder_total = 0
    @cart.items.each do |item|
      product = item[:product]
      qty = item[:quantity]
      s = product.split_immediate_and_pending(qty)
      pending_total += s[:pending]
      preorder_total += (s[:pending_type] == :preorder ? s[:pending] : 0)
      backorder_total += (s[:pending_type] == :backorder ? s[:pending] : 0)
    end
    { pending_total: pending_total, preorder_total: preorder_total, backorder_total: backorder_total }
  end
end
