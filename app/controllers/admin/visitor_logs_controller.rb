# frozen_string_literal: true

module Admin
  class VisitorLogsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    def index
      @visitor_logs = VisitorLog.includes(:user).order(created_at: :desc).limit(200)
    end

    private

    def require_admin!
      redirect_to root_path unless current_user.admin?
    end
  end
end
