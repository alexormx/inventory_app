# frozen_string_literal: true

module Api
  module V1
    class SaleOrderItemsController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_with_token!

      # POST /api/v1/sale_order_items
      def create
        item_params = sale_order_item_params
        so = SaleOrder.find_by(id: item_params[:sale_order_id])
        return render json: { status: 'error', message: 'Sale order not found' }, status: :not_found unless so

        product = find_product(item_params)
        unless product
          return render json: { status: 'error', message: 'Product not found' },
                        status: :unprocessable_entity
        end

        item = so.sale_order_items.build(
          product: product,
          quantity: item_params[:quantity],
          unit_cost: item_params[:unit_cost] || item_params[:unit_final_price],
          unit_discount: item_params[:unit_discount] || 0,
          unit_final_price: item_params[:unit_final_price] || item_params[:unit_cost],
          total_line_cost: item_params[:total_line_cost] || (item_params[:quantity].to_i * (item_params[:unit_final_price] || item_params[:unit_cost]).to_f)
        )
        if item.save
          render json: { status: 'ok', id: item.id }, status: :created
        else
          render json: { status: 'error', errors: item.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/sale_order_items/batch
      def batch
        so = SaleOrder.find_by(id: params[:sale_order_id])
        unless so
          return render json: { status: 'error', message: 'Sale order not found' },
                        status: :unprocessable_entity
        end

        items = params[:items]
        unless items.is_a?(Array)
          return render json: { status: 'error', message: 'items must be an array' },
                        status: :unprocessable_entity
        end

        created = []
        errors = []

        items.each_with_index do |raw, idx|
          # Ensure we work with a plain Hash for nested params arrays
          raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h.symbolize_keys : raw.to_h.symbolize_keys
          product = find_product(raw)
          if product.nil?
            errors << { index: idx, error: 'Product not found', item: raw }
            next
          end

          qty = raw[:quantity].to_i
          unit_cost = BigDecimal((raw[:unit_cost].presence || 0).to_s)
          unit_discount = BigDecimal((raw[:unit_discount].presence || 0).to_s)
          unit_final_price = BigDecimal((raw[:unit_final_price].presence || (unit_cost - unit_discount)).to_s)
          total_line_cost = BigDecimal((raw[:total_line_cost].presence || (qty * unit_final_price)).to_s)

          item = so.sale_order_items.build(
            product: product,
            quantity: qty,
            unit_cost: unit_cost,
            unit_discount: unit_discount,
            unit_final_price: unit_final_price,
            total_line_cost: total_line_cost
          )
          if item.save
            created << item
          else
            errors << { index: idx, error: item.errors.full_messages, item: raw }
          end
        end

        status_code = created.any? ? :created : :unprocessable_entity
        render json: { status: 'ok', created: created.map(&:id), errors: errors }, status: status_code
      end

      private

      def find_product(source)
        h = if source.respond_to?(:to_unsafe_h)
              source.to_unsafe_h.symbolize_keys
            elsif source.respond_to?(:to_h)
              source.to_h.symbolize_keys
            else
              source
            end
        return nil unless h

        if h[:product_id].present?
          Product.find_by(id: h[:product_id])
        elsif h[:product_sku].present?
          Product.find_by(product_sku: h[:product_sku])
        end
      end

      def sale_order_item_params
        params.expect(sale_order_item: %i[sale_order_id product_id product_sku quantity
                                          unit_cost unit_discount unit_final_price total_line_cost])
      end
    end
  end
end
