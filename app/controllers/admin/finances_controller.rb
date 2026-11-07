# frozen_string_literal: true

module Admin
  # Estado de resultados y flujo mensual (o anual en la vista histórica).
  class FinancesController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
    helper Admin::DashboardHelper
    layout 'admin'

    def index
      today = Time.zone.today
      first_year = Finance::MonthlyStatement.first_operation_on&.year || today.year
      @history = params[:view] == 'history'
      year = (Integer(params[:year].to_s, exception: false) || today.year).clamp(first_year, today.year)
      @result = Finance::MonthlyStatement.new(year: @history ? nil : year, today: today).call

      respond_to do |format|
        format.html
        format.csv do
          send_data Finance::StatementCsv.new(@result).call,
                    filename: "finanzas-#{@history ? 'historico' : year}-#{today.iso8601}.csv",
                    type: 'text/csv; charset=utf-8'
        end
      end
    end
  end
end
