# frozen_string_literal: true

class WhatsappListsController < ApplicationController
  layout 'customer'

  before_action :block_signed_in_users, except: %i[track]
  before_action :load_request, except: %i[add_item track]

  # GET /whatsapp-list
  def show
    if @request.nil?
      @items = []
    else
      @items = @request.whatsapp_request_items.includes(:product).order(created_at: :asc)
    end
  end

  # POST /whatsapp-list/items (params: product_id, quantity)
  def add_item
    product = Product.publicly_visible.find(params[:product_id])
    quantity = params[:quantity].to_i
    quantity = 1 if quantity <= 0

    @request = current_or_create_draft

    item = @request.whatsapp_request_items.find_or_initialize_by(product: product)
    current_qty = item.persisted? ? item.quantity : 0
    desired_qty = current_qty + quantity

    if (msg = validate_desired_quantity(product, desired_qty))
      return reject_add_item(msg)
    end

    item.quantity = desired_qty
    item.unit_price_snapshot ||= product.selling_price
    item.save!
    @request.recompute_total!

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: catalog_path, notice: "Agregado a la lista de WhatsApp." }
      format.json { render json: { ok: true, count: @request.total_items } }
    end
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: catalog_path, alert: "Producto no encontrado."
  end

  # PATCH /whatsapp-list/items/:item_id (params: quantity)
  def update_item
    return redirect_to whatsapp_list_path, alert: "Lista vacía." if @request.nil?

    item = @request.whatsapp_request_items.find(params[:item_id])
    new_qty = params[:quantity].to_i

    if new_qty.positive? && (msg = validate_desired_quantity(item.product, new_qty))
      return redirect_to whatsapp_list_path, alert: msg
    end

    if new_qty <= 0
      item.destroy
    else
      item.update!(quantity: new_qty)
    end
    @request.recompute_total!
    redirect_to whatsapp_list_path
  end

  # DELETE /whatsapp-list/items/:item_id
  def remove_item
    return redirect_to whatsapp_list_path, alert: "Lista vacía." if @request.nil?

    @request.whatsapp_request_items.find(params[:item_id]).destroy
    @request.recompute_total!
    redirect_to whatsapp_list_path, notice: "Item eliminado."
  end

  # POST /whatsapp-list/send
  def send_via_whatsapp
    return redirect_to whatsapp_list_path, alert: "Lista vacía." if @request.nil? || @request.whatsapp_request_items.empty?

    @request.assign_attributes(send_params)
    if @request.customer_name.blank?
      flash.now[:alert] = "Tu nombre es necesario para enviar la lista."
      @items = @request.whatsapp_request_items.includes(:product)
      return render :show, status: :unprocessable_entity
    end

    @request.mark_sent!
    tracking_url = track_whatsapp_list_url(code: @request.code) rescue nil
    url = @request.whatsapp_url(tracking_url: tracking_url)
    if url.blank?
      flash[:alert] = "Falta configurar el teléfono de WhatsApp del comercio."
      return redirect_to whatsapp_list_path
    end

    # Limpiamos el cookie para que el siguiente add inicie un draft nuevo
    cookies.delete(:wa_list_token)
    redirect_to url, allow_other_host: true
  end

  # GET /lista/:code  — tracking público sin login
  def track
    @tracked_request = WhatsappRequest.where.not(status: :draft).find_by!(code: params[:code].to_s.upcase)
    render :track
  rescue ActiveRecord::RecordNotFound
    redirect_to whatsapp_list_path, alert: "No encontramos un pedido con ese código."
  end

  private

  def block_signed_in_users
    return unless user_signed_in?

    msg = "La lista de WhatsApp es solo para invitados. Como ya tienes cuenta, usa el carrito de compras."
    respond_to do |format|
      format.turbo_stream { flash[:alert] = msg; redirect_to cart_path }
      format.html { redirect_to cart_path, alert: msg }
      format.json { render json: { error: msg }, status: :forbidden }
    end
  end

  def load_request
    @request = current_request
  end

  def current_request
    token_request
  end

  def token_request
    token = cookies.signed[:wa_list_token]
    return nil if token.blank?

    WhatsappRequest.where(session_token: token, status: :draft).first
  end

  def current_or_create_draft
    existing = current_request
    return existing if existing.present?

    token = SecureRandom.urlsafe_base64(24)
    cookies.signed[:wa_list_token] = { value: token, expires: 60.days.from_now, httponly: true }
    WhatsappRequest.create!(
      session_token: token,
      status: :draft
    )
  end

  def send_params
    params.fetch(:whatsapp_request, {}).permit(:customer_name, :customer_phone, :customer_email, :customer_notes)
  end

  # Aplica las mismas reglas que el carrito (asumiendo brand_new):
  #  - producto activo (Product.publicly_visible ya lo asegura aguas arriba)
  #  - desired <= disponible (available + in_transit) si el producto NO permite preorder/backorder
  #  - desired <= MAX_NEW_ITEMS_PER_PRODUCT
  def validate_desired_quantity(product, desired)
    return "Producto no disponible" unless product.active?

    if desired > Cart::MAX_NEW_ITEMS_PER_PRODUCT
      return "Máximo #{Cart::MAX_NEW_ITEMS_PER_PRODUCT} unidades por producto."
    end

    available = available_brand_new_for(product)
    if desired > available && !product.oversell_allowed?
      return "Stock insuficiente (disponibles: #{available}). Este producto no permite preventa ni sobre pedido."
    end

    nil
  end

  def available_brand_new_for(product)
    product.inventories
           .where(status: %i[available in_transit], item_condition: :brand_new, sale_order_id: nil)
           .count
  end

  def reject_add_item(msg)
    respond_to do |format|
      format.turbo_stream { flash[:alert] = msg; redirect_back fallback_location: catalog_path }
      format.html { redirect_back fallback_location: catalog_path, alert: msg }
      format.json { render json: { error: msg }, status: :unprocessable_entity }
    end
  end
end
