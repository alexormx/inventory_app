# frozen_string_literal: true

module Admin
  class ReceivablesController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    def index
      @receivables = SaleOrder
                     .includes(:user)
                     .with_balance
                     .open_receivables
                     .ordered_due_date_recent
    end
  end
end
