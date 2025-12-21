# frozen_string_literal: true

module Admin
  class VisitorLogsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    def index
      @tab = params[:tab] || 'recent'

      # Métricas globales
      @metrics = {
        total_visits: VisitorLog.sum(:visit_count),
        today_visits: VisitorLog.where('last_visited_at >= ?', Time.current.beginning_of_day).sum(:visit_count),
        unique_visitors: VisitorLog.distinct.count(:ip_address),
        countries: VisitorLog.where.not(country: [nil, '']).distinct.count(:country)
      }

      case @tab
      when 'by_user'
        # Agrupado por usuario/IP
        @by_user = VisitorLog
          .select(
            'COALESCE(user_id, 0) as grouped_user_id',
            'ip_address',
            'MAX(users.email) as user_email',
            'MAX(users.name) as user_name',
            'SUM(visit_count) as total_visits',
            'COUNT(*) as pages_visited',
            'MAX(last_visited_at) as last_activity',
            'MAX(country) as country',
            'MAX(city) as city'
          )
          .left_joins(:user)
          .group('COALESCE(user_id, 0)', 'ip_address')
          .order('last_activity DESC')
          .limit(100)
      when 'by_page'
        # Agrupado por ruta
        @by_page = VisitorLog
          .select(
            'path',
            'SUM(visit_count) as total_visits',
            'COUNT(DISTINCT ip_address) as unique_visitors',
            'MAX(last_visited_at) as last_visit'
          )
          .group(:path)
          .order('total_visits DESC')
          .limit(100)
      when 'by_country'
        # Agrupado por país
        @by_country = VisitorLog
          .where.not(country: [nil, ''])
          .select(
            'country',
            'SUM(visit_count) as total_visits',
            'COUNT(DISTINCT ip_address) as unique_visitors',
            'COUNT(DISTINCT path) as pages_viewed'
          )
          .group(:country)
          .order('total_visits DESC')
      else
        # Reciente (default)
        @visitor_logs = VisitorLog.includes(:user).order(last_visited_at: :desc).page(params[:page]).per(50)
      end
    end

    private

    def require_admin!
      redirect_to root_path unless current_user.admin?
    end
  end
end
