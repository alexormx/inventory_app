class Admin::ShipmentsController < ApplicationController
  before_action :set_sale_order
  before_action :set_shipment, only: [ :edit, :update ]

  def new
    @shipment = @sale_order.build_shipment
    render partial: "admin/shipments/form", locals: { shipment: @shipment, sale_order: @sale_order }
  end

  def create
    if @sale_order.shipment.present?
      @shipment = @sale_order.shipment
      @shipment.errors.add(:base, "Shipment already exists")
      render partial: "admin/shipments/form", locals: { shipment: @shipment, sale_order: @sale_order }, status: :unprocessable_entity
      return
    end

    @shipment = Shipment.new(shipment_params)
    @shipment.sale_order = @sale_order

    if @shipment.save
      @sale_order.reload # ✅ Ensure shipment is attached and loaded
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to admin_sale_order_path(@sale_order), notice: "Shipment created" }
      end
    else
      render partial: "admin/shipments/form", locals: { shipment: @shipment, sale_order: @sale_order }, status: :unprocessable_entity
    end
  end

  def edit
    render partial: "admin/shipments/form", locals: { shipment: @shipment, sale_order: @sale_order }
  end

  def update
    if @shipment.update(shipment_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to admin_sale_order_path(@sale_order), notice: "Shipment updated successfully" }
      end
    else
      render partial: "admin/shipments/form", locals: { shipment: @shipment, sale_order: @sale_order }, status: :unprocessable_entity
    end
  end

  private

  def set_sale_order
    @sale_order = SaleOrder.find(params[:sale_order_id])
  end

  def set_shipment
    @shipment = @sale_order.shipment
  end

  def shipment_params
    params.require(:shipment).permit(:tracking_number, :carrier, :status, :estimated_delivery, :actual_delivery)
  end
end
