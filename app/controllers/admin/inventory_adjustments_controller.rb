# frozen_string_literal: true

module Admin
  class InventoryAdjustmentsController < ApplicationController
    before_action :set_inventory_adjustment, only: %i[show edit update destroy apply reverse]

    # GET /admin/inventory_adjustments
    def index
      @inventory_adjustments = InventoryAdjustment.order(created_at: :desc).page(params[:page])
    end

    # GET /admin/inventory_adjustments/:id
    def show; end

    # GET /admin/inventory_adjustments/new
    def new
      @inventory_adjustment = InventoryAdjustment.new(status: 'draft', adjustment_type: 'audit')
    end

    # GET /admin/inventory_adjustments/:id/edit
    def edit; end

    # POST /admin/inventory_adjustments
    def create
      @inventory_adjustment = InventoryAdjustment.new(inventory_adjustment_params)
      if @inventory_adjustment.save
        redirect_to [:admin, @inventory_adjustment], notice: 'Adjustment created (Draft).'
      else
        flash.now[:alert] = @inventory_adjustment.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /admin/inventory_adjustments/:id
    def update
      if @inventory_adjustment.update(inventory_adjustment_params)
        redirect_to [:admin, @inventory_adjustment], notice: 'Adjustment updated.'
      else
        flash.now[:alert] = @inventory_adjustment.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    # DELETE /admin/inventory_adjustments/:id
    def destroy
      if @inventory_adjustment.status_draft?
        @inventory_adjustment.destroy
        redirect_to admin_inventory_adjustments_path, notice: 'Adjustment deleted.'
      else
        redirect_to [:admin, @inventory_adjustment], alert: 'Cannot delete an applied adjustment. Reverse it first.'
      end
    end

    # POST /admin/inventory_adjustments/:id/apply
    def apply
      @inventory_adjustment.apply!(applied_by: current_user)
      redirect_to [:admin, @inventory_adjustment], notice: 'Adjustment applied.'
    rescue ApplyInventoryAdjustmentService::EmptyAdjustment
      redirect_to [:admin, @inventory_adjustment], alert: 'Adjustment has no lines.'
    rescue ApplyInventoryAdjustmentService::InsufficientStock => e
      redirect_to [:admin, @inventory_adjustment], alert: e.message
    rescue ApplyInventoryAdjustmentService::AlreadyApplied
      redirect_to [:admin, @inventory_adjustment], notice: 'Adjustment already applied.'
    rescue ActiveRecord::RecordInvalid => e
      redirect_to [:admin, @inventory_adjustment], alert: e.record.errors.full_messages.to_sentence
    end

    # POST /admin/inventory_adjustments/:id/reverse
    def reverse
      @inventory_adjustment.reverse!(reversed_by: current_user)
      redirect_to [:admin, @inventory_adjustment], notice: 'Adjustment reversed to Draft.'
    rescue ReverseInventoryAdjustmentService::NotApplied
      redirect_to [:admin, @inventory_adjustment], notice: 'Adjustment is already Draft.'
    rescue ReverseInventoryAdjustmentService::NotReversible => e
      redirect_to [:admin, @inventory_adjustment], alert: e.message
    end

    private

    def set_inventory_adjustment
      @inventory_adjustment = InventoryAdjustment.find(params[:id])
    end

    def inventory_adjustment_params
      params.expect(
        inventory_adjustment: [:status, :adjustment_type, :found_at, :reference, :note, :user_id,
                               { inventory_adjustment_lines_attributes: %i[
                                 id product_id quantity direction reason unit_cost note _destroy
                               ] }]
      )
    end
  end
end
