# frozen_string_literal: true

module Admin
  # Órdenes que requieren atención manual (ver SaleOrders::Alerts). Sólo lectura.
  class OrderAlertsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    def index
      @stale_pending = SaleOrders::Alerts.stale_pending
      @overpaid = SaleOrders::Alerts.overpaid
      @inconsistent = SaleOrders::Alerts.inconsistent
    end
  end
end
