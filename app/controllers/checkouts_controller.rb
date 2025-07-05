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
    @shipping_info = {} # podrías usar un formulario o model aquí
  end

  #create the step 2 submit action
  #this action will save the shipping info in the session
  #and redirect to step 3
  def step2_submit
    shipping_info = {
      full_name: params[:shipping_full_name],
      address: params[:shipping_address],
      city: params[:shipping_city],
      postal_code: params[:shipping_postal_code],
      method: params[:shipping_method]
    }

    # Validación simple (puedes mejorarla luego)
    if shipping_info.values.any?(&:blank?)
      flash.now[:alert] = "Todos los campos son obligatorios."
      render :step2, status: :unprocessable_entity
      return
    end

    session[:shipping_info] = shipping_info
    redirect_to checkout_step3_path
  end

  #step3 is the payment method selection step
  #here you can select the payment method and complete the order
  def step3
    # Mostrar confirmación + seleccionar método de pago
  end


  def complete
    payment_method = params[:payment_method]

    if payment_method.blank?
      flash.now[:alert] = "Selecciona un método de pago."
      render :step3, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      @sale_order = current_user.sale_orders.create!(
        order_date: Date.today,
        subtotal: @cart.total,
        tax_rate: 0,
        total_tax: 0,
        total_order_value: @cart.total,
        notes: session[:checkout_notes],
        status: 'Pending'
      )

      @cart.items.each do |product, qty|
        @sale_order.sale_order_items.create!(
          product: product,
          quantity: qty,
          unit_cost: product.selling_price,
          total_line_cost: product.selling_price * qty
        )
      end

      @sale_order.payments.create!(
        amount: @sale_order.total_order_value,
        payment_method: payment_method,
        status: 'Pending'
      )

      # TODO: También puedes usar session[:shipping_info] para guardarla
    end

    session[:cart] = {}
    session.delete(:checkout_notes)
    session.delete(:shipping_info)

    redirect_to checkout_thank_you_path
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = "Ocurrió un error al procesar la orden: #{e.message}"
    render :step3, status: :unprocessable_entity
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