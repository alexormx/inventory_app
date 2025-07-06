class UsersController < ApplicationController
  before_action :authenticate_user!

  def accept_cookies
    current_user.update(cookies_accepted: true)
    head :ok
  end
end
