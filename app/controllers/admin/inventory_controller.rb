class Admin::InventoryController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    @products_with_inventory = Product.includes(:inventory)
  end

  def items
    @product = Product.find(params[:id])
    @inventory_items = @product.inventory.includes(:purchase_order)
  
    render partial: "admin/inventory/items", locals: { product: @product, items: @inventory_items }
  end

  def edit_status
    @item = Inventory.find(params[:id])
    render partial: "admin/inventory/edit_status_form", locals: { item: @item }
  end
  
  def update_status
    @item = Inventory.find(params[:id])

    if @item.status != "sold" && Inventory.statuses.keys.include?(params[:status])
      @item.update(status: params[:status], status_changed_at: Time.current)
      @product = @item.product
  
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("inventory_status_#{@item.id}", partial: "admin/inventory/status_badge", locals: { item: @item }),
            turbo_stream.replace("inventory-summary-#{@product.id}", partial: "admin/inventory/summary", locals: { product: @product })
          ]
        end
        format.html do
          redirect_to admin_inventory_index_path, notice: "Status updated"
        end
      end
    else
      redirect_to admin_inventory_index_path, alert: "Status could not be updated"
    end
  end

  # Para el botón Cancelar
  def cancel_edit_status
    @item = Inventory.find(params[:id])
    render partial: "admin/inventory/status_badge", locals: { item: @item }
  end

  private
  def inventory_params
    params.require(:inventory).permit(:status, :status_changed_at)
  end

end
