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
    return if request.path.starts_with?("/assets", "/cable")
    return if request.xhr?
    return if !request.format.html?
    return if request.path.in?([
      "/favicon.ico", "/robots.txt", "/sitemap.xml"
    ])

    ip = real_ip_from_cloudflare || request.remote_ip

    VisitorLog.track(
      ip: ip,
      agent: request.user_agent,
      path: request.fullpath,
      user: current_user
    )
  rescue => e
    Rails.logger.warn("IP tracking error: #{e.message}")
  end

  def real_ip_from_cloudflare
    request.headers['CF-Connecting-IP'] || 
    request.headers['X-Forwarded-For']&.split(",")&.first&.strip
  end


end
