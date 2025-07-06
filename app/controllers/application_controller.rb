class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  layout :set_layout
  before_action :track_visitor

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

  def authorize_admin!
    unless current_user.admin?
      flash[:alert] = "Acceso denegado: Solo los administradores pueden acceder a esta sección."
      redirect_to root_path
    end
  end

  def track_visitor
    Rails.logger.debug "🔥 track_visitor ejecutado para #{request.fullpath}"
    
    return if request.path.starts_with?("/assets", "/cable") # esta línea sí puede quedar
    return if request.xhr? # No track AJAX requests
    return if request.format.html? == false # No track non-HTML requests
    return if request.path == "/favicon.ico" # No track favicon requests
    return if request.path == "/robots.txt" # No track robots.txt requests
    return if request.path == "/sitemap.xml" # No track sitemap requests

    VisitorLog.track(
      ip: request.remote_ip,
      agent: request.user_agent,
      path: request.fullpath,
      user: current_user
    )
  rescue => e
    Rails.logger.warn("IP tracking error: #{e.message}")
  end


end
