module Introspection
  SENSITIVE_ENV_PATTERNS = /(SECRET|PASSWORD|KEY|TOKEN|DATABASE_URL|RAILS_MASTER_KEY)/i

  # Env as a sorted, filtered hash without sensitive keys
  def self.filtered_env(env = ENV)
    env.to_h.select { |k, _| k.present? && k !~ SENSITIVE_ENV_PATTERNS }
       .sort.to_h
  end

  # Lightweight runtime/app info; safe to call anytime
  def self.app_info
    {
      rails_env: (Rails.env if defined?(Rails)),
      ruby_version: RUBY_VERSION,
      rails_version: (Rails.version if defined?(Rails)),
      time: Time.now,
      pid: Process.pid,
      memory_mb: begin
        rss_kb = `ps -o rss= -p #{Process.pid}`.to_i
        rss_kb.positive? ? (rss_kb / 1024) : nil
      rescue StandardError
        nil
      end
    }
  end

  # Safe wrappers around the heavy introspection reports
  def self.safe_schema_report
    Introspection::SchemaReport.call
  rescue => e
    { error: "SchemaReport failed: #{e.class}: #{e.message}" }
  end

  def self.safe_model_report
    Introspection::ModelReport.call
  rescue => e
    { error: "ModelReport failed: #{e.class}: #{e.message}" }
  end

  def self.safe_env_usage_report
    Introspection::EnvUsageReport.call
  rescue => e
    { error: "EnvUsageReport failed: #{e.class}: #{e.message}" }
  end
end
