# frozen_string_literal: true

module Api
  module V1
    class SalesOrdersController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_with_token!

      # POST /api/v1/sales_orders
      def create
        user = User.find_by(email: sales_order_params[:email])
        unless user
          render json: { status: 'error', message: "User not found for email #{sales_order_params[:email]}" },
                 status: :unprocessable_entity and return
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
          'pending' => 'Pending',
          'confirmed' => 'Confirmed',
          'preparing' => 'Preparing',
          'shipped' => 'Shipped',
          'delivered' => 'Delivered',
          'canceled' => 'Canceled',
          'cancelled' => 'Canceled'
        }

        desired_status = if so_attrs[:status].present?
                           mapping[so_attrs[:status].to_s.strip.downcase] || so_attrs[:status].to_s.strip.capitalize
                         else
                           'Pending'
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
            sale_order_attrs[:status] = 'Pending'

            sales_order = SaleOrder.create!(sale_order_attrs)

            # Crear payment si el estado deseado es Confirmed o Delivered
            if %w[Confirmed Delivered].include?(desired_status)
              # Solo crear pago si el total de la orden es mayor a 0
              if sales_order.total_order_value.to_f > 0.0
                pm_param = params.dig(:sales_order, :payment_method).presence
                pm_mapped = if pm_param && Payment.payment_methods.keys.include?(pm_param.to_s)
                              pm_param.to_s
                            else
                              'transferencia_bancaria'
                            end

                paid_at_ts = begin
                  base_date = sales_order.order_date || Time.zone.today
                  (base_date.to_time.in_time_zone + 5.days)
                rescue StandardError
                  Time.zone.now
                end

                payment = sales_order.payments.create!(
                  amount: sales_order.total_order_value,
                  status: 'Completed',
                  payment_method: pm_mapped,
                  paid_at: paid_at_ts
                )

                response_extra[:payment] = payment
              else
                response_extra[:payment] = { skipped_for_zero_amount: true }
              end
            end

            # Crear shipment si el estado deseado es Delivered
            if desired_status == 'Delivered'
              expected = begin
                Date.parse(params.dig(:sales_order, :expected_delivery_date)) if params.dig(:sales_order, :expected_delivery_date).present?
              rescue StandardError
                nil
              end

              actual = begin
                Date.parse(params.dig(:sales_order, :actual_delivery_date)) if params.dig(:sales_order, :actual_delivery_date).present?
              rescue StandardError
                nil
              end

              order_base_date = sales_order.order_date || Time.zone.today
              expected ||= (order_base_date + 20)
              actual ||= expected

              tracking = params.dig(:sales_order, :tracking_number).presence || 'A00000000MX'
              carrier = params.dig(:sales_order, :carrier).presence || 'Local'

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
            if desired_status != 'Pending'
              # Recargar para asegurar que asociaciones persistan, y actualizar con callbacks/validaciones
              sales_order.reload
              sales_order.update!(status: desired_status)
            end
            render_success(sales_order, response_extra)
            return
          end
        rescue ActiveRecord::RecordInvalid => e
          render_unprocessable_entity(e)
        rescue StandardError => e
          render_internal_error(e)
        end
      end

      # PATCH/PUT /api/v1/sales_orders/:id
      def update
        sales_order = SaleOrder.find_by(id: params[:id])
        render json: { status: 'error', message: 'SaleOrder not found' }, status: :not_found and return unless sales_order

        # Permitimos mismo set que en create (email es ignorado aquí)
        attrs = sales_order_params.except(:email).to_h.symbolize_keys

        # Parseo/normalización del estado deseado
        mapping = {
          'pending' => 'Pending',
          'confirmed' => 'Confirmed',
          'preparing' => 'Preparing',
          'shipped' => 'Shipped',
          'delivered' => 'Delivered',
          'canceled' => 'Canceled',
          'cancelled' => 'Canceled'
        }
        desired_status = if attrs[:status].present?
                           mapping[attrs[:status].to_s.strip.downcase] || attrs[:status].to_s.strip.capitalize
                         else
                           sales_order.status
                         end

        # Recalcular totales solo si se envían campos financieros en el payload
        if %i[subtotal tax_rate discount shipping_cost].any? { |k| attrs.key?(k) && attrs[k].present? }
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
            incoming_status = update_attrs.delete(:status)

            requires_payment_now = [sales_order.status, desired_status].any? { |st| %w[Confirmed Delivered].include?(st) }
            missing_payment = sales_order.total_order_value.to_f > 0.0 && sales_order.total_paid < sales_order.total_order_value

            if requires_payment_now && missing_payment && %w[Delivered Confirmed].include?(sales_order.status)
              # La orden ya está en estado que exige pago y no lo tiene: evitar validaciones, actualizar totales (si vinieron) y crear Payment primero.
              financial_keys = %i[subtotal tax_rate discount total_tax total_order_value]
              financial_update = update_attrs.slice(*financial_keys)
              other_updates = update_attrs.except(*financial_keys)

              # Aplicar campos no críticos sin cambiar status (sin validaciones)
              sales_order.update_columns(other_updates) if other_updates.present?
              sales_order.update_columns(financial_update) if financial_update.present?

              # Crear Payment por el faltante
              pm_param = params.dig(:sales_order, :payment_method).presence
              pm_mapped = if pm_param && Payment.payment_methods.keys.include?(pm_param.to_s)
                            pm_param.to_s
                          else
                            'transferencia_bancaria'
                          end

              paid_at_ts = begin
                base_date = sales_order.order_date || Time.zone.today
                (base_date.to_time.in_time_zone + 5.days)
              rescue StandardError
                Time.zone.now
              end

              payment = sales_order.payments.create!(
                amount: (sales_order.total_order_value - sales_order.total_paid),
                status: 'Completed',
                payment_method: pm_mapped,
                paid_at: paid_at_ts
              )
              response_extra[:payment] = payment

              # Shipment si ya es o será Delivered
              if (desired_status == 'Delivered' || sales_order.status == 'Delivered') && sales_order.shipment.blank?
                expected = begin
                  Date.parse(params.dig(:sales_order, :expected_delivery_date)) if params.dig(:sales_order, :expected_delivery_date).present?
                rescue StandardError
                  nil
                end

                actual = begin
                  Date.parse(params.dig(:sales_order, :actual_delivery_date)) if params.dig(:sales_order, :actual_delivery_date).present?
                rescue StandardError
                  nil
                end

                order_base_date = sales_order.order_date || Time.zone.today
                expected ||= (order_base_date + 20)
                actual ||= expected

                tracking = params.dig(:sales_order, :tracking_number).presence || 'A00000000MX'
                carrier = params.dig(:sales_order, :carrier).presence || 'Local'

                shipment = sales_order.create_shipment!(
                  tracking_number: tracking,
                  carrier: carrier,
                  estimated_delivery: expected,
                  actual_delivery: actual,
                  status: Shipment.statuses[:delivered]
                )
                response_extra[:shipment] = shipment
              end

              # Aplicar status deseado (si viene), sin validaciones
              sales_order.update!(status: desired_status) if incoming_status.present? && desired_status != sales_order.status
            else
              # Flujo normal: actualizamos con validaciones y luego garantizamos payment/shipment si el estado deseado lo requiere
              sales_order.update!(update_attrs)

              if %w[Confirmed
                    Delivered].include?(desired_status) && (sales_order.total_order_value.to_f > 0.0 && sales_order.total_paid < sales_order.total_order_value)
                pm_param = params.dig(:sales_order, :payment_method).presence
                pm_mapped = if pm_param && Payment.payment_methods.keys.include?(pm_param.to_s)
                              pm_param.to_s
                            else
                              'transferencia_bancaria'
                            end

                paid_at_ts = begin
                  base_date = sales_order.order_date || Time.zone.today
                  (base_date.to_time.in_time_zone + 5.days)
                rescue StandardError
                  Time.zone.now
                end

                payment = sales_order.payments.create!(
                  amount: sales_order.total_order_value - sales_order.total_paid,
                  status: 'Completed',
                  payment_method: pm_mapped,
                  paid_at: paid_at_ts
                )
                response_extra[:payment] = payment
              end

              if desired_status == 'Delivered' && sales_order.shipment.blank?
                expected = begin
                  Date.parse(params.dig(:sales_order, :expected_delivery_date)) if params.dig(:sales_order, :expected_delivery_date).present?
                rescue StandardError
                  nil
                end

                actual = begin
                  Date.parse(params.dig(:sales_order, :actual_delivery_date)) if params.dig(:sales_order, :actual_delivery_date).present?
                rescue StandardError
                  nil
                end

                order_base_date = sales_order.order_date || Time.zone.today
                expected ||= (order_base_date + 20)
                actual ||= expected

                tracking = params.dig(:sales_order, :tracking_number).presence || 'A00000000MX'
                carrier = params.dig(:sales_order, :carrier).presence || 'Local'

                shipment = sales_order.create_shipment!(
                  tracking_number: tracking,
                  carrier: carrier,
                  estimated_delivery: expected,
                  actual_delivery: actual,
                  status: Shipment.statuses[:delivered]
                )
                response_extra[:shipment] = shipment
              end

              sales_order.update!(status: desired_status) if incoming_status.present? || desired_status != sales_order.status
            end

            render json: { status: 'success', sales_order: sales_order.reload, extra: response_extra }, status: :ok and return
          end
        rescue ActiveRecord::RecordInvalid => e
          render json: { status: 'error', errors: e.record.errors.full_messages }, status: :unprocessable_entity and return
        rescue StandardError => e
          render json: { status: 'error', message: e.message }, status: :internal_server_error and return
        end
      end

        private

        def render_success(sales_order, extra)
          return if performed?
          render json: { status: 'success', sales_order: sales_order, extra: extra }, status: :created
        end

        def render_unprocessable_entity(exception)
          return if performed?
          render json: { status: 'error', errors: exception.record.errors.full_messages }, status: :unprocessable_entity
        end

        def render_internal_error(exception)
          return if performed?
          render json: { status: 'error', message: exception.message }, status: :internal_server_error
        end

      # POST /api/v1/sales_orders/:id/recalculate_and_pay
      # Recalcula totales desde las líneas y crea el pago faltante (Completed) y shipment (si Delivered) evitando bloqueos.
      def recalculate_and_pay
        sales_order = SaleOrder.find_by(id: params[:id])
        render json: { status: 'error', message: 'SaleOrder not found' }, status: :not_found and return unless sales_order

        response_extra = {}

        begin
          ActiveRecord::Base.transaction do
            # 1) Recalcular totales desde items si existen
            before_total = sales_order.total_order_value
            items_count = sales_order.sale_order_items.count
            sales_order.recalculate_totals!(persist: true)
            sales_order.reload
            # Si sigue en cero, derivarlo desde líneas y persistir columnas mínimas
            if sales_order.total_order_value.to_f <= 0.0 && items_count.positive?
              items_total = sales_order.sale_order_items.sum(<<~SQL.squish)
                COALESCE(total_line_cost,
                         quantity * COALESCE(unit_final_price, (unit_cost - COALESCE(unit_discount, 0))))
              SQL
              items_total = items_total.to_d.round(2)
              if items_total.positive?
                sales_order.update_columns(subtotal: items_total, total_tax: 0, total_order_value: items_total, updated_at: Time.current)
                sales_order.reload
              end
            end
            Rails.logger.info({ at: 'Api::V1::SalesOrdersController#recalculate_and_pay:recalc', id: sales_order.id, before_total: before_total&.to_s,
                                after_total: sales_order.total_order_value.to_s, items_count: items_count }.to_json)
            response_extra[:recalculated] = { before: before_total, after: sales_order.total_order_value, items: items_count }

            # 2) Si no está completamente pagada y el total > 0, crear pago por el faltante (Completed)
            if sales_order.total_order_value.to_f > 0.0 && sales_order.total_paid < sales_order.total_order_value
              pm_param = params.dig(:payment, :payment_method).presence || params.dig(:sales_order, :payment_method).presence
              pm_mapped = if pm_param && Payment.payment_methods.keys.include?(pm_param.to_s)
                            pm_param.to_s
                          else
                            'transferencia_bancaria'
                          end

              paid_at_ts = begin
                base_date = sales_order.order_date || Time.zone.today
                (base_date.to_time.in_time_zone + 5.days)
              rescue StandardError
                Time.zone.now
              end

              missing = (sales_order.total_order_value - sales_order.total_paid).round(2)
              payment = sales_order.payments.create!(
                amount: missing,
                status: 'Completed',
                payment_method: pm_mapped,
                paid_at: paid_at_ts
              )
              response_extra[:payment] = payment
              Rails.logger.info({ at: 'Api::V1::SalesOrdersController#recalculate_and_pay:payment_created', id: sales_order.id,
                                  amount: missing.to_s }.to_json)
            else
              response_extra[:payment] = { skipped: true, reason: 'already_fully_paid_or_zero_total' }
              Rails.logger.info({ at: 'Api::V1::SalesOrdersController#recalculate_and_pay:payment_skipped', id: sales_order.id,
                                  total: sales_order.total_order_value.to_s, total_paid: sales_order.total_paid.to_s }.to_json)
            end

            # 3) Si la orden está Delivered y no hay shipment, crear uno por defecto
            if sales_order.status == 'Delivered' && sales_order.shipment.blank?
              order_base_date = sales_order.order_date || Time.zone.today
              expected = order_base_date + 20
              shipment = sales_order.create_shipment!(
                tracking_number: 'A00000000MX',
                carrier: 'Local',
                estimated_delivery: expected,
                actual_delivery: expected,
                status: Shipment.statuses[:delivered]
              )
              response_extra[:shipment] = shipment
            end

            render json: { status: 'success', sales_order: sales_order.reload, extra: response_extra }, status: :ok and return
          end
        rescue ActiveRecord::RecordInvalid => e
          render json: { status: 'error', errors: e.record.errors.full_messages }, status: :unprocessable_entity and return
        rescue StandardError => e
          render json: { status: 'error', message: e.message }, status: :internal_server_error and return
        end
      end

      # POST /api/v1/sales_orders/:id/ensure_payment
      # Idempotente: recalcula totales si es necesario y crea el pago por el faltante si aplica.
      def ensure_payment
        sales_order = SaleOrder.find_by(id: params[:id])
        render json: { status: 'error', message: 'SaleOrder not found' }, status: :not_found and return unless sales_order

        pm_param = params.dig(:payment, :payment_method).presence || params.dig(:sales_order, :payment_method).presence
        pm_mapped = if pm_param && Payment.payment_methods.keys.include?(pm_param.to_s)
                      pm_param.to_s
                    else
                      'transferencia_bancaria'
                    end

        begin
          result = ::SaleOrders::EnsurePaymentService.new(sales_order, payment_method: pm_mapped).call
          if result.created
            render json: { status: 'success', created_amount: result.created_amount.to_s }, status: :created
          else
            render json: { status: 'success', message: result.skipped_reason || 'no_action' }, status: :ok
          end
        rescue ActiveRecord::RecordInvalid => e
          render json: { status: 'error', errors: e.record.errors.full_messages }, status: :unprocessable_entity
        rescue StandardError => e
          render json: { status: 'error', message: e.message }, status: :internal_server_error
        end
      end

      private

      def sales_order_params
        params.expect(sales_order: %i[id order_date subtotal tax_rate total_tax discount total_order_value status email notes
                                      shipping_cost tracking_number carrier expected_delivery_date actual_delivery_date payment_method])
      end
    end
  end
end
