require 'rake'

# Asegurar carga de servicios Introspection en entornos con autoload estricto
begin
  require_dependency Rails.root.join('app/services/introspection/schema_report').to_s
  require_dependency Rails.root.join('app/services/introspection/model_report').to_s
  require_dependency Rails.root.join('app/services/introspection/env_usage_report').to_s
rescue StandardError
  # No-op: en dev/CI puede no ser necesario; en prod ayuda a evitar NameError
end

class Admin::SystemVariablesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_admin!

  # Muestra variables provenientes de varios orígenes:
  # 1. ENV (filtradas para evitar secretos sensibles)
  # 2. SiteSetting registros en DB
  # 3. Rails.configuration / credentials (llaves no secretas)
  # 4. Feature flags / dinámicas (placeholder)
  # 5. Stats runtime (Rails env, versión Ruby, memoria aproximada)
  def index
    @env_vars = filtered_env
    @site_settings = SiteSetting.order(:key)
    @rails_config = gather_rails_config
    @runtime_info = runtime_info
    @dynamic_flags = dynamic_flags
  @schema_report = ::Introspection::SchemaReport.call
  @model_report  = ::Introspection::ModelReport.call
  @env_usage_report = ::Introspection::EnvUsageReport.call
  end

  # Ejecuta la generación / actualización de placeholders de comentarios (no destructivo)
  def generate_schema_docs
    authorize_admin!
    begin
      # Cargar tareas sólo una vez; reenable para permitir múltiples invocaciones web
      Rails.application.load_tasks unless Rake::Task.task_defined?('introspection:generate_schema_docs')
      task = Rake::Task['introspection:generate_schema_docs']
      task.reenable
      task.invoke
      redirect_to admin_system_variables_path, notice: 'Schema docs regenerado (placeholders actualizados).'
    rescue => e
      redirect_to admin_system_variables_path, alert: "Fallo al regenerar schema docs: #{e.class}: #{e.message}"
    end
  end

  private
  SENSITIVE_ENV_PATTERNS = /(SECRET|PASSWORD|KEY|TOKEN|DATABASE_URL|RAILS_MASTER_KEY)/i

  def filtered_env
    ENV.to_h.select { |k,_| k.present? && k !~ SENSITIVE_ENV_PATTERNS }
            .sort.to_h
  end

  def gather_rails_config
    cfg = {}
    # Ejemplos de configuración útil (ampliable)
  cs = Rails.configuration.cache_store
  cfg[:cache_store] = cs.is_a?(Array) ? cs.first : cs
    cfg[:active_storage_service] = Rails.configuration.active_storage.service
    cfg[:eager_load] = Rails.configuration.eager_load
    cfg[:consider_all_requests_local] = Rails.configuration.consider_all_requests_local
    cfg[:host] = Rails.application.config.action_controller.default_url_options&.dig(:host)
    cfg
  rescue => e
    { error: e.message }
  end

  def runtime_info
    {
      rails_env: Rails.env,
      ruby_version: RUBY_VERSION,
      rails_version: Rails.version,
      time: Time.current,
      pid: Process.pid,
      memory_mb: (`ps -o rss= -p #{Process.pid}`.to_i / 1024 rescue nil)
    }
  end

  def dynamic_flags
    # Lugar para centralizar toggles o banderas en variables de entorno / settings
    {
      cookie_banner_enabled: ENV['COOKIE_BANNER_ENABLED'] || 'true',
      preload_images: ENV['PRELOAD_IMAGES'] || 'false'
    }
  end
end
