class Api::V1::PurchaseOrderItemsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :authenticate_with_token!

  # POST /api/v1/purchase_order_items
  def create
  render json: { status: 'error', message: 'Use /api/v1/purchase_order_items/batch' }, status: :method_not_allowed
  end

  # POST /api/v1/purchase_order_items/batch
  def batch
    po = PurchaseOrder.find_by(id: params[:purchase_order_id])
    return render json: { status: 'error', message: 'Purchase order not found' }, status: :unprocessable_entity unless po

    items = params[:items]
    return render json: { status: 'error', message: 'items must be an array' }, status: :unprocessable_entity unless items.is_a?(Array)

    # Prepare products and basic lines (quantity, unit_cost) and compute total volume/weight
    lines = []
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
      if qty <= 0
        errors << { index: idx, error: 'quantity must be > 0', item: raw }
        next
      end
      unit_cost = BigDecimal((raw[:unit_cost].presence || 0).to_s)

      unit_volume = (product.length_cm.to_f * product.width_cm.to_f * product.height_cm.to_f)
      unit_weight = product.weight_gr.to_f
      line_volume = qty * unit_volume
      line_weight = qty * unit_weight

      lines << {
        index: idx,
        product: product,
        qty: qty,
        unit_cost: unit_cost,
        unit_volume: unit_volume,
        unit_weight: unit_weight,
        line_volume: line_volume,
        line_weight: line_weight
      }
    end

    total_lines_volume = lines.sum { |l| l[:line_volume] }
    total_lines_weight = lines.sum { |l| l[:line_weight] }

    total_additional_cost = BigDecimal(po.shipping_cost.to_s) + BigDecimal(po.tax_cost.to_s) + BigDecimal(po.other_cost.to_s)
    exchange_rate = BigDecimal((po.exchange_rate.presence || 1).to_s)

    created = []

    ActiveRecord::Base.transaction do
      lines.each do |l|
        volume_rate_per_unit = total_lines_volume > 0 ? (l[:unit_volume] / total_lines_volume) : 0.0
        unit_additional_cost = (total_additional_cost * BigDecimal(volume_rate_per_unit.to_s)).round(2)
        unit_compose_cost = (l[:unit_cost] + unit_additional_cost).round(2)
        unit_compose_cost_mxn = (unit_compose_cost * exchange_rate).round(2)

        line_total_cost = (l[:qty] * unit_compose_cost).round(2)
        line_total_cost_mxn = (line_total_cost * exchange_rate).round(2)

        item = po.purchase_order_items.build(
          product: l[:product],
          quantity: l[:qty],
          unit_cost: l[:unit_cost],
          unit_additional_cost: unit_additional_cost,
          unit_compose_cost: unit_compose_cost,
          unit_compose_cost_in_mxn: unit_compose_cost_mxn,
          total_line_volume: l[:line_volume],
          total_line_weight: l[:line_weight],
          total_line_cost: line_total_cost,
          total_line_cost_in_mxn: line_total_cost_mxn
        )

        unless item.save
          raise ActiveRecord::Rollback, "Row #{l[:index]}: #{item.errors.full_messages.to_sentence}"
        end

        created << {
          id: item.id,
          product_id: item.product_id,
          quantity: item.quantity,
          unit_cost: item.unit_cost,
          unit_additional_cost: item.unit_additional_cost,
          unit_compose_cost: item.unit_compose_cost,
          unit_compose_cost_in_mxn: item.unit_compose_cost_in_mxn,
          total_line_volume: item.total_line_volume,
          total_line_weight: item.total_line_weight,
          total_line_cost: item.total_line_cost,
          total_line_cost_in_mxn: item.total_line_cost_in_mxn
        }
      end

      # Update PO totals based on the same logic as the UI
      po_subtotal = lines.sum { |l| (l[:qty] * l[:unit_cost]).to_d }
      po_total_volume = total_lines_volume
      po_total_weight = total_lines_weight
      po_total_order_cost = (po_subtotal + total_additional_cost).round(2)
      po_total_cost_mxn = (po_total_order_cost * exchange_rate).round(2)

      po.update!(
        subtotal: po_subtotal,
        total_volume: po_total_volume,
        total_weight: po_total_weight,
        total_order_cost: po_total_order_cost,
        total_cost_mxn: po_total_cost_mxn
      )
    end

    status_code = created.any? ? :created : :unprocessable_entity
    render json: { status: 'ok', created: created, errors: errors }, status: status_code
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

  def purchase_order_item_params
    params.require(:purchase_order_item).permit(:purchase_order_id, :product_id, :product_sku, :quantity,
      :unit_cost, :unit_additional_cost, :unit_compose_cost, :unit_compose_cost_in_mxn)
  end
end
