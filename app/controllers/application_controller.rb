class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  layout :set_layout

  protected
  def after_sign_in_path_for(resource)
    if resource.admin?
      admin_dashboard_path
    else
      root_path
    end
  end

  private
  def set_layout
    if current_user&.admin?
      "admin"
    else
      "customer"
    end
  end
end
