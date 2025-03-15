class Admin::SettingsController < ApplicationController
  before_action :authorize_admin!

  def index
    # Settings logic
  end
end
