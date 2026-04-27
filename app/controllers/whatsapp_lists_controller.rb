# frozen_string_literal: true

class WhatsappListsController < ApplicationController
  layout 'customer'

  before_action :load_request, except: [:add_item]

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
    item.quantity = (item.persisted? ? item.quantity : 0) + quantity
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
    url = @request.whatsapp_url
    if url.blank?
      flash[:alert] = "Falta configurar el teléfono de WhatsApp del comercio."
      return redirect_to whatsapp_list_path
    end

    # Limpiamos el cookie para que el siguiente add inicie un draft nuevo
    cookies.delete(:wa_list_token)
    redirect_to url, allow_other_host: true
  end

  private

  def load_request
    @request = current_request
  end

  def current_request
    if user_signed_in?
      WhatsappRequest.where(user: current_user, status: :draft).order(created_at: :desc).first ||
        token_request
    else
      token_request
    end
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
      user: (user_signed_in? ? current_user : nil),
      session_token: token,
      status: :draft
    )
  end

  def send_params
    params.fetch(:whatsapp_request, {}).permit(:customer_name, :customer_phone, :customer_email, :customer_notes)
  end
end
