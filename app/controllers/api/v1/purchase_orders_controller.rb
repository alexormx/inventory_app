# frozen_string_literal: true

module Api
  module V1
    class PurchaseOrdersController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_with_token!

      # POST /api/v1/purchase_orders
      def create
        user = User.find_by(email: purchase_order_params[:email])
        unless user
          render json: { status: 'error', message: "User not found for email #{purchase_order_params[:email]}" }, 
                 status: :unprocessable_entity and return
        end

        po_attrs = purchase_order_params.except(:email).merge(user_id: user.id)

        # Compute and persist total_cost_mxn consistently for reporting/UI
        begin
          currency = po_attrs[:currency].to_s
          total_order_cost = BigDecimal(po_attrs[:total_order_cost].to_s)
          exchange_rate = BigDecimal((po_attrs[:exchange_rate].presence || 0).to_s)

          total_cost_mxn = if currency == 'MXN'
                             total_order_cost
                           elsif exchange_rate.positive?
                             total_order_cost * exchange_rate
                           else
                             0
                           end

          po_attrs[:total_cost_mxn] = total_cost_mxn.round(2)
        rescue ArgumentError
          po_attrs[:total_cost_mxn] = 0
        end
        purchase_order = PurchaseOrder.new(po_attrs)

        if purchase_order.save
          render json: { status: 'success', purchase_order: purchase_order }, status: :created
        else
          render json: { status: 'error', errors: purchase_order.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def purchase_order_params
        params.expect(purchase_order: %i[id order_date currency exchange_rate tax_cost shipping_cost other_cost subtotal total_order_cost
                                         status email expected_delivery_date actual_delivery_date])
      end
    end
  end
end

