class Api::V1::SalesOrdersController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_with_token!

  # POST /api/v1/sales_orders
  def create
    user = User.find_by(email: sales_order_params[:email])
    unless user
      render json: { status: "error", message: "User not found for email #{sales_order_params[:email]}" }, status: :unprocessable_entity and return
    end

    so_attrs = sales_order_params.except(:email).merge(user_id: user.id)

    # Compute totals
    begin
      subtotal = BigDecimal((so_attrs[:subtotal].presence || 0).to_s)
      tax_rate = BigDecimal((so_attrs[:tax_rate].presence || 0).to_s)
      discount = BigDecimal((so_attrs[:discount].presence || 0).to_s)
      shipping_cost = BigDecimal((so_attrs[:shipping_cost].presence || 0).to_s)

      total_tax = (subtotal * (tax_rate / 100)).round(2)
      # Include shipping_cost into total (legacy data sometimes only set shipping)
      total_order_value = (subtotal + total_tax + shipping_cost - discount).round(2)

      so_attrs[:total_tax] = total_tax
      so_attrs[:total_order_value] = total_order_value
      so_attrs[:subtotal] = subtotal.round(2)
      so_attrs[:discount] = discount.round(2)
      # shipping_cost is not a column on SaleOrder; it's only used to compute totals
    rescue ArgumentError
      so_attrs[:total_tax] = 0
      so_attrs[:total_order_value] = 0
      so_attrs[:subtotal] = 0
      so_attrs[:discount] = 0
      # ignore shipping_cost on parse errors
    end

    # Normalizar estado deseado (el que viene en el payload)
    mapping = {
      "pending" => "Pending",
      "confirmed" => "Confirmed",
      "shipped" => "Shipped",
      "delivered" => "Delivered",
      "canceled" => "Canceled",
      "cancelled" => "Canceled"
    }

    desired_status = if so_attrs[:status].present?
                       mapping[so_attrs[:status].to_s.strip.downcase] || so_attrs[:status].to_s.strip.capitalize
                     else
                       "Pending"
                     end

    response_extra = {}

    begin
      ActiveRecord::Base.transaction do
  # Solo pasar atributos que pertenecen realmente al modelo SaleOrder
  allowed = SaleOrder.attribute_names.map(&:to_sym)
  sale_order_attrs = so_attrs.slice(*allowed)

  # Crear inicialmente la orden en Pending para evitar validaciones que
  # requieran payment/shipment antes de que existan. Luego actualizamos
  # el estado final (see below).
  sale_order_attrs[:status] = "Pending"

  sales_order = SaleOrder.create!(sale_order_attrs)

        # Crear payment si el estado deseado es Confirmed o Delivered
        if %w[Confirmed Delivered].include?(desired_status)
          # Solo crear pago si el total de la orden es mayor a 0
          if sales_order.total_order_value.to_f > 0.0
            pm_param = params.dig(:sales_order, :payment_method).presence
            pm_mapped = if pm_param && Payment.payment_methods.keys.include?(pm_param.to_s)
                          pm_param.to_s
                        else
                          "transferencia_bancaria"
                        end

            paid_at_ts = begin
              base_date = sales_order.order_date || Date.today
              (base_date.to_time.in_time_zone + 5.days)
            rescue StandardError
              Time.zone.now
            end

            payment = sales_order.payments.create!(
              amount: sales_order.total_order_value,
              status: "Completed",
              payment_method: pm_mapped,
              paid_at: paid_at_ts
            )

            response_extra[:payment] = payment
          else
            response_extra[:payment] = { skipped_for_zero_amount: true }
          end
        end

        # Crear shipment si el estado deseado es Delivered
        if desired_status == "Delivered"
          expected = begin
            if params.dig(:sales_order, :expected_delivery_date).present?
              Date.parse(params.dig(:sales_order, :expected_delivery_date))
            else
              nil
            end
          rescue StandardError
            nil
          end

          actual = begin
            if params.dig(:sales_order, :actual_delivery_date).present?
              Date.parse(params.dig(:sales_order, :actual_delivery_date))
            else
              nil
            end
          rescue StandardError
            nil
          end

          order_base_date = sales_order.order_date || Date.today
          expected ||= (order_base_date + 20)
          actual ||= expected

          tracking = params.dig(:sales_order, :tracking_number).presence || "A00000000MX"
          carrier = params.dig(:sales_order, :carrier).presence || "Local"

          shipment = sales_order.create_shipment!(
            tracking_number: tracking,
            carrier: carrier,
            estimated_delivery: expected,
            actual_delivery: actual,
            status: Shipment.statuses[:delivered]
          )

          response_extra[:shipment] = shipment
        end

        # Ahora actualizamos el estado al deseado (ya existen payment/shipment si se requieren)
        if desired_status != "Pending"
          # Recargar para asegurar que asociaciones persistan, y actualizar columna
          sales_order.reload
          sales_order.update_columns(status: desired_status)
        end

        render json: { status: "success", sales_order: sales_order, extra: response_extra }, status: :created and return
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { status: "error", errors: e.record.errors.full_messages }, status: :unprocessable_entity and return
    rescue StandardError => e
      render json: { status: "error", message: e.message }, status: :internal_server_error and return
    end
  end

  # PATCH/PUT /api/v1/sales_orders/:id
  def update
    sales_order = SaleOrder.find_by(id: params[:id])
    unless sales_order
      render json: { status: "error", message: "SaleOrder not found" }, status: :not_found and return
    end

    # Permitimos mismo set que en create (email es ignorado aquí)
    attrs = sales_order_params.except(:email).to_h.symbolize_keys

    # Parseo/normalización del estado deseado
    mapping = {
      "pending" => "Pending",
      "confirmed" => "Confirmed",
      "shipped" => "Shipped",
      "delivered" => "Delivered",
      "canceled" => "Canceled",
      "cancelled" => "Canceled"
    }
    desired_status = if attrs[:status].present?
                        mapping[attrs[:status].to_s.strip.downcase] || attrs[:status].to_s.strip.capitalize
                      else
                        sales_order.status
                      end

    # Recalcular totales solo si se envían campos financieros en el payload
    if [:subtotal, :tax_rate, :discount, :shipping_cost].any? { |k| attrs.key?(k) && attrs[k].present? }
      begin
        subtotal = BigDecimal((attrs[:subtotal].presence || sales_order.subtotal || 0).to_s)
        tax_rate = BigDecimal((attrs[:tax_rate].presence || sales_order.tax_rate || 0).to_s)
        discount = BigDecimal((attrs[:discount].presence || sales_order.discount || 0).to_s)
        shipping_cost = BigDecimal((attrs[:shipping_cost].presence || 0).to_s)

        total_tax = (subtotal * (tax_rate / 100)).round(2)
        total_order_value = (subtotal + total_tax + shipping_cost - discount).round(2)

        attrs[:total_tax] = total_tax
        attrs[:total_order_value] = total_order_value
        attrs[:subtotal] = subtotal.round(2)
        attrs[:discount] = discount.round(2)
      rescue ArgumentError
        # Dejar los valores actuales si hay error de parseo
        attrs.delete(:total_tax)
        attrs.delete(:total_order_value)
        attrs.delete(:subtotal)
        attrs.delete(:discount)
      end
    end

    response_extra = {}

    begin
      ActiveRecord::Base.transaction do
        # No permitimos sobrescribir user_id por seguridad desde aquí
        allowed = SaleOrder.attribute_names.map(&:to_sym) - [:user_id]
        update_attrs = attrs.slice(*allowed)

        # Primero actualizamos datos base (sin forzar estado imposible)
        # Si el estado deseado requiere payment/shipment, los creamos antes de setear status
        incoming_status = update_attrs.delete(:status)

        sales_order.update!(update_attrs)

        # Si el estado final será Confirmed o Delivered, aseguramos payment completo
        if %w[Confirmed Delivered].include?(desired_status)
          if sales_order.total_order_value.to_f > 0.0 && sales_order.total_paid < sales_order.total_order_value
            pm_param = params.dig(:sales_order, :payment_method).presence
            pm_mapped = if pm_param && Payment.payment_methods.keys.include?(pm_param.to_s)
                          pm_param.to_s
                        else
                          "transferencia_bancaria"
                        end

            paid_at_ts = begin
              base_date = sales_order.order_date || Date.today
              (base_date.to_time.in_time_zone + 5.days)
            rescue StandardError
              Time.zone.now
            end

            payment = sales_order.payments.create!(
              amount: sales_order.total_order_value - sales_order.total_paid,
              status: "Completed",
              payment_method: pm_mapped,
              paid_at: paid_at_ts
            )
            response_extra[:payment] = payment
          end
        end

        # Si el estado final será Delivered, aseguramos shipment presente
        if desired_status == "Delivered" && sales_order.shipment.blank?
          expected = begin
            if params.dig(:sales_order, :expected_delivery_date).present?
              Date.parse(params.dig(:sales_order, :expected_delivery_date))
            else
              nil
            end
          rescue StandardError
            nil
          end

          actual = begin
            if params.dig(:sales_order, :actual_delivery_date).present?
              Date.parse(params.dig(:sales_order, :actual_delivery_date))
            else
              nil
            end
          rescue StandardError
            nil
          end

          order_base_date = sales_order.order_date || Date.today
          expected ||= (order_base_date + 20)
          actual ||= expected

          tracking = params.dig(:sales_order, :tracking_number).presence || "A00000000MX"
          carrier = params.dig(:sales_order, :carrier).presence || "Local"

          shipment = sales_order.create_shipment!(
            tracking_number: tracking,
            carrier: carrier,
            estimated_delivery: expected,
            actual_delivery: actual,
            status: Shipment.statuses[:delivered]
          )
          response_extra[:shipment] = shipment
        end

        # Finalmente, aplicamos el status deseado
        if incoming_status.present? || desired_status != sales_order.status
          sales_order.update_columns(status: desired_status)
        end

        render json: { status: "success", sales_order: sales_order.reload, extra: response_extra }, status: :ok and return
      end
    rescue ActiveRecord::RecordInvalid => e
      render json: { status: "error", errors: e.record.errors.full_messages }, status: :unprocessable_entity and return
    rescue StandardError => e
      render json: { status: "error", message: e.message }, status: :internal_server_error and return
    end
  end

  private

  def sales_order_params
    params.require(:sales_order).permit(:id, :order_date, :subtotal, :tax_rate, :total_tax, :discount, :total_order_value, :status, :email, :notes,
      :shipping_cost, :tracking_number, :carrier, :expected_delivery_date, :actual_delivery_date, :payment_method)
  end
end
