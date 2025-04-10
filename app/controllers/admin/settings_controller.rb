class Admin::SettingsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  def index
    # Settings logic
  end
end
