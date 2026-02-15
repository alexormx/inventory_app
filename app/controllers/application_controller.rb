# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include ApiTokenAuthenticatable
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  layout :set_layout
  before_action :track_visitor
  before_action :ensure_confirmed_user!
  before_action :set_locale
  helper Admin::SortHelper if defined?(Admin::SortHelper)

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
      'admin'
    else
      'customer'
    end
  end

  def authorize_admin!
    return if current_user.admin?

    flash[:alert] = 'Acceso denegado: Solo los administradores pueden acceder a esta sección.'
    redirect_to root_path
  end

  def track_visitor
    return if request.path.starts_with?('/assets', '/cable')
    return if request.xhr?
    return unless request.format.html?
    return if request.path.in?([
                                 '/favicon.ico', '/robots.txt', '/sitemap.xml'
                               ])

    ip = real_ip_from_cloudflare || request.remote_ip

    VisitorLog.track(
      ip: ip,
      agent: request.user_agent,
      path: request.fullpath,
      user: current_user
    )
  rescue StandardError => e
    Rails.logger.warn("IP tracking error: #{e.message}")
  end

  def real_ip_from_cloudflare
    request.headers['CF-Connecting-IP'] ||
      request.headers['X-Forwarded-For']&.split(',')&.first&.strip
  end

  def ensure_confirmed_user!
    return unless current_user && !current_user.confirmed?

    sign_out current_user
    flash[:alert] = 'Debes confirmar tu correo electrónico antes de continuar.'
    redirect_to new_user_session_path
  end

  def set_locale
    chosen = params[:locale]&.to_sym
    session[:locale] = chosen if chosen && I18n.available_locales.include?(chosen)
    I18n.locale = session[:locale] || I18n.default_locale
  end

  def default_url_options
    { locale: (I18n.locale unless I18n.locale == I18n.default_locale) }.compact
  end
end
