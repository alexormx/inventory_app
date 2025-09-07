require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module InventoryApp
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0
    config.app_name = "Pasatiempos"
    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
  # Asegurar que app/services está en autoload/eager_load paths
  services_path = Rails.root.join('app/services')
    config.autoload_paths << services_path unless config.autoload_paths.include?(services_path)
    config.eager_load_paths << services_path unless config.eager_load_paths.include?(services_path)
    config.eager_load_paths << Rails.root.join('app/services', 'preorders') unless config.eager_load_paths.include?(Rails.root.join('app/services', 'preorders'))
    config.autoload_lib(ignore: %w[ assets tasks ])

    # Add i18n configuration to your application.
    config.i18n.available_locales = [ :"es-MX", :es, :en ]
    config.i18n.default_locale = :"es-MX"
    config.i18n.fallbacks = { :"es-MX" => :es }

    config.active_record.schema_format = :ruby if Rails.env.test?
    config.active_record.dump_schema_after_migration = true

    config.whatsapp_number = ENV.fetch("WHATSAPP_NUMBER", "525555555555")

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
