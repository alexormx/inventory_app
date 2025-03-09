class Admin::DashboardController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
     # Dashboard logic goes here
  end

  private
  def authorize_admin!
    redirect_to root_path, alert: "Not authorized." unless current_user.admin?
  end
end
