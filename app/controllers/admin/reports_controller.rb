class Admin::ReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    # Generate reports logic
  end
end
