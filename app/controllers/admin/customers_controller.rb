# frozen_string_literal: true

module Admin
  class CustomersController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_customer, only: %i[edit update]

    def index
      @customers = User.where(role: 'customer').order(created_at: :desc).page(params[:page]).per(20)
      @purchase_stats = PurchaseOrder.where(user_id: @customers.map(&:id))
                                     .group(:user_id)
                                     .pluck(:user_id, Arel.sql('SUM(total_cost_mxn) AS total_value'), Arel.sql('MAX(order_date) AS last_date'))
                                     .to_h.transform_values { |v| { total_value: v[0], last_date: v[1] } }
      @sales_stats = SaleOrder.where(user_id: @customers.map(&:id))
                              .group(:user_id)
                              .pluck(:user_id, Arel.sql('SUM(total_order_value) AS total_value'), Arel.sql('MAX(order_date) AS last_date'))
                              .to_h.transform_values { |v| { total_value: v[0], last_date: v[1] } }
      @last_visits = VisitorLog.where(user_id: @customers.map(&:id)).group(:user_id).maximum(:last_visited_at)
    end

    def new
      @customer = User.new(role: 'customer')
    end

    def edit
      # @customer is already set by the before_action
    end

    def create
      @customer = User.new(user_params)
      @customer.role = 'customer'
      @customer.password = Devise.friendly_token.first(12) # generate a random password

      if @customer.save
        redirect_to admin_customers_path, notice: 'Customer created successfully.'
      else
        flash.now[:alert] = 'Failed to create customer.'
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @customer = User.find(params[:id])
      if @customer.update(user_params)
        redirect_to admin_customers_path, notice: 'Customer updated successfully.'
      else
        flash.now[:alert] = 'Failed to update customer.'
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_customer
      @customer = User.find(params[:id])
      return if @customer.role == 'customer'

      redirect_to admin_customers_path, alert: 'Not a customer.'
      
    end

    def user_params
      params.expect(user: %i[name email phone address discount_rate created_offline notes])
    end
  end
end
