# frozen_string_literal: true

module Admin
  class AdminsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    before_action :set_admin, only: %i[edit update]

    def index
      @admins = User.where(role: 'admin').order(created_at: :desc).page(params[:page]).per(20)
      user_ids = @admins.map(&:id)
      @purchase_stats = PurchaseOrder.where(user_id: user_ids)
                                     .group(:user_id)
                                     .pluck(:user_id, Arel.sql('SUM(total_cost_mxn) AS total_value'), Arel.sql('MAX(order_date) AS last_date'))
                                     .to_h.transform_values { |v| { total_value: v[0], last_date: v[1] } }
      @sales_stats = SaleOrder.where(user_id: user_ids)
                              .group(:user_id)
                              .pluck(:user_id, Arel.sql('SUM(total_order_value) AS total_value'), Arel.sql('MAX(order_date) AS last_date'))
                              .to_h.transform_values { |v| { total_value: v[0], last_date: v[1] } }
      @last_visits = VisitorLog.where(user_id: user_ids).group(:user_id).maximum(:last_visited_at)
    end

    def show
      @user = User.find(params[:id])
    end

    def new
      @admin = User.new(role: 'admin')
    end

    def edit; end

    def create
      @admin = User.new(admin_params.merge(role: 'admin'))
      @admin.password = Devise.friendly_token.first(12)

      if @admin.save
        redirect_to admin_admins_path, notice: 'Admin created.'
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      if @admin.update(admin_params)
        redirect_to admin_admins_path, notice: 'Admin updated.'
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_admin
      @admin = User.find(params[:id])
    end

    def admin_params
      params.expect(user: %i[name email phone address])
    end
  end
end