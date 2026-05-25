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

  BOT_USER_AGENT_REGEX = /bot|crawl|spider|slurp|bingpreview|facebookexternalhit|whatsapp|telegram|preview|pingdom|monitor|ahrefs|semrush|mj12/i
  TRACKER_SKIP_PREFIXES = %w[/assets /cable /rails /admin].freeze
  TRACKER_SKIP_PATHS = %w[/favicon.ico /robots.txt /sitemap.xml /up].freeze

  def track_visitor
    return if request.xhr?
    return unless request.format.html?
    return if TRACKER_SKIP_PREFIXES.any? { |prefix| request.path.starts_with?(prefix) }
    return if TRACKER_SKIP_PATHS.include?(request.path)

    ua = request.user_agent.to_s
    return if ua.match?(BOT_USER_AGENT_REGEX)

    ip = real_ip_from_cloudflare || request.remote_ip

    VisitorLogs::TrackJob.perform_later(
      ip: ip,
      agent: ua,
      path: request.fullpath,
      user_id: current_user&.id,
      referrer: request.referrer.to_s.presence
    )
  rescue StandardError => e
    Rails.logger.warn("[track_visitor] enqueue error: #{e.message}")
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
