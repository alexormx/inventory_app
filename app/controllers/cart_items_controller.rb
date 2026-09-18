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

    # Disponibilidad canónica por condición: la compra normal se satisface con
    # inventario DISPONIBLE AHORA; lo que excede eso solo se permite como
    # reservación explícita (ver #orderable_ceiling).
    availability = condition_availability
    current_in_cart = @cart.quantity_for(@product.id, condition: @condition)
    desired_total = current_in_cart + 1

    # Validar stock disponible
    if desired_total > orderable_ceiling(availability)
      msg = if @collectible
              'Esta pieza coleccionable ya no está disponible.'
            else
              "Stock insuficiente (#{availability_sentence(availability)}). " \
                'Este producto no permite preventa ni sobre pedido.'
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
    availability = condition_availability
    available_count = orderable_quantity(availability)
    max_allowed = @cart.max_allowed(@condition)

    # Validar stock
    if desired.positive? && desired > orderable_ceiling(availability)
      msg = "No puedes agregar #{desired} unidades. #{availability_sentence(availability)}."
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

  # Disponibilidad canónica de la condición solicitada, compartida con el
  # catálogo y la ficha de producto (Inventories::Availability).
  def condition_availability
    Inventories::Availability.for(@product, condition: @condition)
  end

  # Tope de unidades que se pueden pedir de esta condición.
  #
  # La compra NORMAL se satisface únicamente con inventario DISPONIBLE AHORA
  # (:available, con ubicación física, sin sale_order). Por encima de eso la
  # línea solo se admite como RESERVACIÓN explícita, nunca como "Agregar":
  #
  #   - preventa / sobre pedido (#oversell_allowed?): sin tope de stock, su
  #     flujo dedicado decide (ver InventoryServices::AvailabilitySplitter).
  #   - piezas ya compradas y en tránsito: reservables; el catálogo etiqueta
  #     ese CTA como "Reservar · Llega <fecha>", jamás como "Agregar".
  def orderable_ceiling(availability)
    return Float::INFINITY if @product.oversell_allowed?

    orderable_quantity(availability)
  end

  def orderable_quantity(availability)
    availability.available_now + availability.in_transit
  end

  # No etiquetamos como "disponible" un número que mezcla stock inmediato con
  # piezas que aún vienen en camino: se reportan por separado.
  def availability_sentence(availability)
    parts = ["Disponible ahora: #{availability.available_now}"]
    parts << "en tránsito reservable: #{availability.in_transit}" if availability.in_transit.positive?
    parts.join(', ')
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
