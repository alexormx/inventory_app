# frozen_string_literal: true

class CheckoutsController < ApplicationController
  include CheckoutSessionHelper

  layout 'customer'
  before_action :authenticate_user!
  before_action :set_cart, except: [:thank_you]
  before_action :ensure_cart_not_empty, except: %i[thank_you complete]

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
    redirect_to checkout_step3_path
  end

  # step3 is the payment method selection step
  # here you can select the payment method and complete the order
  def step3
    # Mostrar confirmación + seleccionar método de pago
    @shipping_info = checkout_shipping_info
    @selected_address = (current_user.shipping_addresses.find_by(id: @shipping_info[:address_id]) if @shipping_info[:address_id])

    if @shipping_info.blank? || @selected_address.nil? || @shipping_info[:method].blank?
      redirect_to checkout_step2_path, alert: 'Faltan datos de envío. Selecciona una dirección y un método de envío.'
      return
    end

    unless ShippingMethod.active.exists?(code: @shipping_info[:method])
      redirect_to checkout_step2_path, alert: 'El método de envío seleccionado ya no está disponible.'
      return
    end

    # Generar token de idempotencia si no existe
    generate_checkout_token! if checkout_token.blank?
  end

  def complete
    checkout_token_param = params[:checkout_token]
    stored_token = checkout_token

    if checkout_token_param.blank?
      flash[:alert] = 'Token de checkout faltante. Intenta nuevamente.'
      redirect_to(checkout_step3_path) and return
    end

    token_matches_session = stored_token.present? &&
                            ActiveSupport::SecurityUtils.secure_compare(checkout_token_param, stored_token)
    existing_order = current_user.sale_orders.find_by(idempotency_key: checkout_token_param)
    if existing_order && (stored_token.blank? || token_matches_session)
      clear_checkout_session! if token_matches_session
      flash[:notice] = 'Esta orden ya fue procesada anteriormente.'
      redirect_to checkout_thank_you_path(order_id: existing_order.id)
      return
    end

    if stored_token.blank?
      flash[:alert] = 'Token de checkout expirado o faltante. Intenta nuevamente.'
      redirect_to(checkout_step3_path) and return
    end

    unless token_matches_session
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

    unless ShippingMethod.active.exists?(code: shipping_info[:method])
      flash[:alert] = 'El método de envío seleccionado ya no está disponible.'
      redirect_to(checkout_step2_path) and return
    end

    # Validar carrito no vacío
    unless @cart.present? && @cart.items.any?
      flash[:alert] = 'Tu carrito está vacío.'
      redirect_to(root_path) and return
    end

    # Validar método de pago usando PaymentMethod de la base de datos
    payment_method = params[:payment_method]
    payment_method_record = PaymentMethod.active.checkout_compatible.find_by(code: payment_method)
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
      # The database constraint is authoritative. Recover only when the same
      # user/token order exists; adapter-specific exception text is not stable.
      existing_order = current_user.sale_orders.find_by(idempotency_key: stored_token)
      raise e unless existing_order

      clear_checkout_session!
      flash[:notice] = 'Esta orden ya fue procesada anteriormente.'
      redirect_to checkout_thank_you_path(order_id: existing_order.id)
    end
  end

  # Página de agradecimiento con resumen del pedido
  def thank_you
    @order = current_user.sale_orders
                         .includes(
                           :order_shipping_address,
                           :payments,
                           sale_order_items: [
                             :inventory_units,
                             { product: { product_images_attachments: :blob } }
                           ]
                         )
                         .find_by(id: params[:order_id])
    return if @order

    redirect_to root_path, alert: 'Pedido no encontrado.' and return
  end

  private

  def set_cart
    @cart = Cart.new(session)
  end

  def ensure_cart_not_empty
    redirect_to cart_path, alert: 'Tu carrito está vacío.' if @cart.empty?
  end
end
