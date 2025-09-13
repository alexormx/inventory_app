class CheckoutsController < ApplicationController
  layout "customer"
  before_action :authenticate_user!
  before_action :set_cart
  before_action :ensure_cart_not_empty

  def step1
    @cart_items = @cart.items
  end

  def step1_submit
    session[:checkout_notes] = params[:notes]
    redirect_to checkout_step2_path
  end

  def step2
  # Pre-cargar selección previa si el usuario vuelve del paso 3 o tras error
  @shipping_info = session[:shipping_info] || {}
  end

  #create the step 2 submit action
  #this action will save the shipping info in the session
  #and redirect to step 3
  def step2_submit
  Rails.logger.info "[Checkout] step2_submit params: #{params.to_unsafe_h.inspect}"
    raw_addr_id = params[:selected_address_id].presence
    raw_method  = params[:shipping_method].presence

    # Fallbacks: dirección default, o primera; método estándar
    addr = if raw_addr_id
             current_user.shipping_addresses.find_by(id: raw_addr_id)
           end
    addr ||= current_user.shipping_addresses.find_by(default: true)
    addr ||= current_user.shipping_addresses.first

    method = raw_method || 'standard'

    if addr.nil?
      flash.now[:alert] = "Necesitas agregar al menos una dirección antes de continuar."
      @shipping_info = {}
      render :step2, status: :unprocessable_entity and return
    end

    unless %w[standard express pickup].include?(method)
      flash.now[:alert] = "Método de envío inválido."
      @shipping_info = { address_id: addr.id }
      render :step2, status: :unprocessable_entity and return
    end

  session[:shipping_info] = { 'address_id' => addr.id, 'method' => method }
  Rails.logger.info "[Checkout] Stored shipping_info in session: #{session[:shipping_info].inspect}"
    redirect_to checkout_step3_path
  end

  #step3 is the payment method selection step
  #here you can select the payment method and complete the order
  def step3
    # Mostrar confirmación + seleccionar método de pago
    raw = session[:shipping_info] || {}
    # Normalizar claves (symbols/strings)
    @shipping_info = {
      address_id: raw[:address_id] || raw['address_id'],
      method: raw[:method] || raw['method']
    }.compact
    @selected_address = if @shipping_info[:address_id]
                          current_user.shipping_addresses.find_by(id: @shipping_info[:address_id])
                        end
    Rails.logger.info "[Checkout] step3 session shipping_info: #{@shipping_info.inspect}; selected_address: #{@selected_address&.id}"
    if @shipping_info.blank? || @selected_address.nil? || @shipping_info[:method].blank?
      flash.now[:alert] = 'Faltan datos de envío (debug).'
      # No redirigimos inmediatamente para poder ver la vista y depurar.
    end
  end


  def complete
    payment_method = params[:payment_method]
    if payment_method.blank?
      flash.now[:alert] = "Selecciona un método de pago."
      step3
      render :step3, status: :unprocessable_entity and return
    end

    shipping_info = session[:shipping_info] || {}
  # Normalizar claves (pueden ser strings en la sesión)
  address_id = shipping_info[:address_id] || shipping_info['address_id']
  method = shipping_info[:method] || shipping_info['method']

    # Validar aceptación de pendientes si aplica (lo revalida el servicio al recalcular availability)
    if params[:accept_pending].blank?
      # Checar rápido si existe algún pending potencial para pedir aceptación explícita
      needs_accept = @cart.items.any? do |product, qty|
        sp = product.split_immediate_and_pending(qty)
        sp[:pending].positive? && [:preorder, :backorder].include?(sp[:pending_type])
      end
      if needs_accept
        flash.now[:alert] = "Debes aceptar los tiempos extendidos de entrega para continuar."
        step3
        render :step3, status: :unprocessable_entity and return
      end
    end

    # (Futuro) idempotency_key = params[:checkout_token]
    result = Checkout::CreateOrder.new(
      user: current_user,
      cart: @cart,
      shipping_address_id: address_id,
      shipping_method: method,
      payment_method: payment_method,
      notes: session[:checkout_notes],
      idempotency_key: nil
    ).call

    unless result.success?
      flash.now[:alert] = result.errors.join('. ')
      step3
      render :step3, status: :unprocessable_entity and return
    end

    @sale_order = result.sale_order
    session[:cart] = {}
    session.delete(:checkout_notes)
    session.delete(:shipping_info)
    redirect_to checkout_thank_you_path
  end

  # Aquí podrías enviar un correo de confirmación o notificación
  def thank_you
    # puedes mostrar un resumen básico si lo deseas
  end

  private

  def set_cart
    @cart = Cart.new(session)
  end

  def ensure_cart_not_empty
    redirect_to cart_path, alert: 'Tu carrito está vacío.' if @cart.empty?
  end
end