class Admin::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!
  layout "admin"

  def index
    @total_products = Product.count
    @total_users = User.count
    @total_orders = PurchaseOrder.count
  end

  # Returns JSON with geo aggregates for map visualizations
  # { visits: [{ name: "Mexico", value: 120 }], visits_by_region: [{ country: "Mexico", region: "Jalisco", value: 30 }],
  #   sales_by_region: [{ country: "Mexico", region: "CDMX", value: 9999.99 }], sales_by_country: [{ name: "Mexico", value: 120000.0 }] }
  def geo
    # Visits by country and region from VisitorLog
    visits_country = VisitorLog.where.not(country: [nil, ""]).group(:country).sum(:visit_count)
    visits_by_country = visits_country.map { |country, count| { name: country, value: count.to_i } }

    visits_region = VisitorLog.where.not(country: [nil, ""], region: [nil, ""]).group(:country, :region).sum(:visit_count)
    visits_by_region = visits_region.map { |(country, region), count| { country:, region:, value: count.to_i } }

    # Sales by country/region placeholder – will use shipping address when available.
    # For now, try infer from User.address basic region tokens if present (best-effort, optional)
    sales_by_region = []
    sales_by_country = []

    respond_to do |format|
      format.json do
        render json: {
          visits: visits_by_country,
          visits_by_region: visits_by_region,
          sales_by_region: sales_by_region,
          sales_by_country: sales_by_country
        }
      end
    end
  end

  private
  def authorize_admin!
    redirect_to root_path, alert: "Not authorized." unless current_user.admin?
  end
end
