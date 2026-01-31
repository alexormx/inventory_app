# frozen_string_literal: true

class CheckoutsController < ApplicationController
  include CheckoutSessionHelper

  layout 'customer'
  before_action :authenticate_user!
  before_action :set_cart
  before_action :ensure_cart_not_empty

  def step1
    @cart_items = @cart.items
  end

  def step1_submit
    set_checkout_notes(params[:notes])
    redirect_to checkout_step2_path
  end

  def step2
    # Pre-cargar selección previa si el usuario vuelve del paso 3 o tras error
    @shipping_info = checkout_shipping_info
  end

  # create the step 2 submit action
  # this action will save the shipping info in the session
  # and redirect to step 3
  def step2_submit
    Rails.logger.info "[Checkout] step2_submit params: #{params.to_unsafe_h.inspect}"
    raw_addr_id = params[:selected_address_id].presence
    raw_method  = params[:shipping_method].presence

    # Fallbacks: dirección default, o primera; método estándar
    addr = (current_user.shipping_addresses.find_by(id: raw_addr_id) if raw_addr_id)
    addr ||= current_user.shipping_addresses.find_by(default: true)
    addr ||= current_user.shipping_addresses.first

    method = raw_method || 'standard'

    if addr.nil?
      flash.now[:alert] = 'Necesitas agregar al menos una dirección antes de continuar.'
      @shipping_info = {}
      render :step2, status: :unprocessable_entity and return
    end

    # Validar que el método de envío existe y está activo
    shipping_method = ShippingMethod.active.find_by(code: method)
    unless shipping_method
      flash.now[:alert] = 'Método de envío inválido.'
      @shipping_info = { address_id: addr.id }
      render :step2, status: :unprocessable_entity and return
    end

    set_checkout_shipping_info(address_id: addr.id, method: method)
    Rails.logger.info "[Checkout] Stored shipping_info in session: #{checkout_shipping_info.inspect}"
    redirect_to checkout_step3_path
  end

  # step3 is the payment method selection step
  # here you can select the payment method and complete the order
  def step3
    # Mostrar confirmación + seleccionar método de pago
    @shipping_info = checkout_shipping_info
    @selected_address = (current_user.shipping_addresses.find_by(id: @shipping_info[:address_id]) if @shipping_info[:address_id])
    Rails.logger.info "[Checkout] step3 session shipping_info: #{@shipping_info.inspect}; selected_address: #{@selected_address&.id}"

    # Generar token de idempotencia si no existe
    if checkout_token.blank?
      generate_checkout_token!
      Rails.logger.info "[Checkout] Generated checkout token: #{checkout_token}"
    end

    return unless @shipping_info.blank? || @selected_address.nil? || @shipping_info[:method].blank?

    flash.now[:alert] = 'Faltan datos de envío (debug).'
    # No redirigimos inmediatamente para poder ver la vista y depurar.
  end

  def complete
    checkout_token_param = params[:checkout_token]
    stored_token = checkout_token

    if checkout_token_param.blank?
      flash[:alert] = 'Token de checkout faltante. Intenta nuevamente.'
      redirect_to(checkout_step3_path) and return
    end

    if stored_token.blank?
      flash[:alert] = 'Token de checkout expirado o faltante. Intenta nuevamente.'
      redirect_to(checkout_step3_path) and return
    end

    unless ActiveSupport::SecurityUtils.secure_compare(checkout_token_param, stored_token)
      flash[:alert] = 'Token de checkout inválido. Intenta nuevamente.'
      redirect_to(checkout_step3_path) and return
    end

    # Validar shipping_info
    shipping_info = checkout_shipping_info
    unless shipping_info[:address_id].present? && shipping_info[:method].present?
      flash[:alert] = 'Falta información de envío.'
      redirect_to(checkout_step2_path) and return
    end

    # Resolver address
    shipping_address = current_user.shipping_addresses.find_by(id: shipping_info[:address_id])
    unless shipping_address
      flash[:alert] = 'Dirección de envío no encontrada.'
      redirect_to(checkout_step2_path) and return
    end

    # Validar carrito no vacío
    unless @cart.present? && @cart.items.any?
      flash[:alert] = 'Tu carrito está vacío.'
      redirect_to(root_path) and return
    end

    # Validar método de pago usando PaymentMethod de la base de datos
    payment_method = params[:payment_method]
    payment_method_record = PaymentMethod.active.find_by(code: payment_method)
    unless payment_method_record
      flash[:alert] = 'Método de pago inválido.'
      redirect_to(checkout_step3_path) and return
    end

    # Preparar order_params
    order_params = {
      user: current_user,
      cart: @cart,
      shipping_address_id: shipping_address.id,
      shipping_method: shipping_info[:method],
      payment_method: payment_method,
      notes: checkout_notes,
      idempotency_key: stored_token
    }

    # Verificar si ya existe una orden con este token (idempotencia)
    existing_order = current_user.sale_orders.find_by(idempotency_key: stored_token) if stored_token.present?
    if existing_order
      Rails.logger.info "[Checkout] Order already exists with token #{stored_token}"
      clear_checkout_session!
      flash[:notice] = 'Esta orden ya fue procesada anteriormente.'
      redirect_to checkout_thank_you_path(order_id: existing_order.id)
      return
    end

    # Intentar crear orden
    begin
      result = Checkout::CreateOrder.new(**order_params).call

      if result.success?
        # Limpiar sesión exitosa
        clear_checkout_session!

        flash[:notice] = "¡Gracias! Tu pedido ##{result.sale_order.id} fue creado exitosamente."
        redirect_to checkout_thank_you_path(order_id: result.sale_order.id)
      else
        # Mostrar errores de validación de la orden
        flash[:alert] = "No se pudo crear tu pedido: #{result.errors.join(', ')}"
        redirect_to checkout_step3_path
      end
    rescue ActiveRecord::RecordNotUnique => e
      # Clave duplicada: orden ya fue creada con este token (race condition)
      raise e unless e.message.include?('sale_orders.index_sale_orders_on_user_and_idempotency')

      flash[:notice] = 'Esta orden ya fue procesada anteriormente.'
      # Intentar encontrar la orden existente
      existing_order = current_user.sale_orders.find_by(idempotency_key: stored_token)
      if existing_order
        clear_checkout_session!
        redirect_to checkout_thank_you_path(order_id: existing_order.id)
      else
        redirect_to checkout_step1_path
      end



    end
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