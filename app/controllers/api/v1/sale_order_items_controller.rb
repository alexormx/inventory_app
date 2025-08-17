class Api::V1::SaleOrderItemsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_with_token!

  # POST /api/v1/sale_order_items
  def create
  render json: { status: 'error', message: 'Use /api/v1/sale_order_items/batch' }, status: :method_not_allowed
  end

  # POST /api/v1/sale_order_items/batch
  def batch
    so = SaleOrder.find_by(id: params[:sale_order_id])
    return render json: { status: 'error', message: 'Sale order not found' }, status: :unprocessable_entity unless so

    items = params[:items]
    return render json: { status: 'error', message: 'items must be an array' }, status: :unprocessable_entity unless items.is_a?(Array)

    created = []
    errors = []

    items.each_with_index do |raw, idx|
      raw = raw.symbolize_keys
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
    if source[:product_id].present?
      Product.find_by(id: source[:product_id])
    elsif source[:product_sku].present?
      Product.find_by(product_sku: source[:product_sku])
    else
      nil
    end
  end

  def sale_order_item_params
    params.require(:sale_order_item).permit(:sale_order_id, :product_id, :product_sku, :quantity,
      :unit_cost, :unit_discount, :unit_final_price, :total_line_cost)
  end
end
