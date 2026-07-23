# frozen_string_literal: true

module Admin
  class PurchaseOrderItemsController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!
  end
end
