class HealthController < ActionController::Base
  # Minimal controller, no authentication, to confirm boot
  def show
    render plain: 'OK', status: :ok
  end
end
