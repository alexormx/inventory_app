# frozen_string_literal: true

module Admin
  class InventoryEventsController < ApplicationController
    before_action :authorize_admin!

    def index
      @events = InventoryEvent.order(created_at: :desc).limit(500)
    end
  end
end
