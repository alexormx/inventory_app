# frozen_string_literal: true

require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort('The Rails environment is running in production mode!') if Rails.env.production?

# Add these environment variables early to suppress errors
ENV['DISABLE_DBUS'] = '1' # Disables D-Bus related warnings
ENV['DBUS_SESSION_BUS_ADDRESS'] = File::NULL # More effective D-Bus suppression
ENV['CUDA_VISIBLE_DEVICES'] = '-1' # Disables GPU attempts
ENV['TF_CPP_MIN_LOG_LEVEL'] = '2' # Reduces TensorFlow logging

require 'rspec/rails'
require 'capybara/rspec'
require 'selenium-webdriver'
require 'devise'

# Ensure Devise mappings are loaded (workaround if not automatically loaded in Rails 8 test env)
Rails.application.reload_routes! if Devise.mappings.empty?

# Load support files
Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# --- Capybara + Selenium setup ---
Capybara.default_max_wait_time = 7
Capybara.javascript_driver = :selenium_chrome_headless
# Keep failure artifacts in a predictable place so CI can upload them.
Capybara.save_path = Rails.root.join('tmp/capybara')

# Resolve chromedriver across environments: the local Chromium path does not exist on
# GitHub Actions runners, which publish a Chrome-matched driver via CHROMEWEBDRIVER/PATH.
CHROMEDRIVER_PATH = [
  ENV.fetch('CHROMEDRIVER_PATH', nil),
  ENV.fetch('CHROMEWEBDRIVER', nil) && File.join(ENV.fetch('CHROMEWEBDRIVER', nil), 'chromedriver'),
  '/usr/lib/chromium-browser/chromedriver'
].compact.find { |path| File.executable?(path) }

# Tamaño de ventana fijo para toda la suite de sistema.
#
# La ventana por defecto de Chrome headless es 800x600, y encima los specs
# responsive la dejan donde acaban (390x844, 575x800, 1024x768...) sin
# restaurarla. Como Selenium reutiliza la misma ventana entre ejemplos y
# config.order = :random, cada ejemplo heredaba un viewport distinto según lo
# que hubiera corrido antes: por eso la suite completa fallaba en CI en un spec
# distinto cada vez, y por eso ese mismo spec pasaba al correrlo solo.
#
# A 800x600 el admin se apila y el panel fijo de avisos queda encima de los
# botones alineados a la derecha, que es como aparecía el click interceptado.
#
# Los specs responsive siguen redimensionando a lo que necesiten; esto sólo
# garantiza que cada ejemplo arranque desde un escritorio conocido.
SYSTEM_SPEC_WINDOW_SIZE = [1440, 1000].freeze

Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument('--headless=new')
  options.add_argument('--disable-gpu')
  options.add_argument('--disable-dev-shm-usage')
  options.add_argument('--no-sandbox')
  options.add_argument('--disable-dev-shm-usage')
  # FIX: Add Accept header to prevent 406 Not Acceptable errors with Rails 7/Turbo
  # options.add_argument('--header=Accept=text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9')

  # Configure the driver to be silent
  service =
    if CHROMEDRIVER_PATH
      Selenium::WebDriver::Service.chrome(path: CHROMEDRIVER_PATH)
    else
      Selenium::WebDriver::Service.chrome
    end

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options, service: service)
end

RSpec.configure do |config|
  # Fixtures / Rails noise
  config.fixture_paths = Rails.root.join('spec/fixtures')
  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!

  # Skip system specs by default for CI stability; enable with RUN_SYSTEM_SPECS=1
  config.filter_run_excluding type: :system unless ENV['RUN_SYSTEM_SPECS'] == '1'

  # Automatically tag specs based on their file location (e.g., spec/requests => type: :request)
  config.infer_spec_type_from_file_location!

  # Deshabilitar Bullet para tests marcados con :skip_bullet
  # Útil para tests de dashboard y otras vistas complejas con muchas queries
  config.around(:each, :skip_bullet) do |example|
    if defined?(Bullet)
      prev_bullet = Bullet.enable?
      Bullet.enable = false
      example.run
      Bullet.enable = prev_bullet
    else
      example.run
    end
  end

  # Helpers
  config.include Rails.application.routes.url_helpers
  config.include FactoryBot::Syntax::Methods
  # Devise helpers
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :feature
  config.include Devise::Test::IntegrationHelpers
  config.include ActiveSupport::Testing::TimeHelpers

  # Provide devise mapping automatically for controller specs to avoid manual @request.env setup
  config.before(:each, type: :controller) do
    @request.env['devise.mapping'] = Devise.mappings[:user]
  end

  # Default URL options (for *_url helpers & Devise mailers)
  config.before(:suite) do
    # Ensure routes are fully loaded for request specs
    Rails.application.reload_routes!
    Rails.application.routes.default_url_options[:host] = 'localhost'
    Rails.application.routes.default_url_options[:protocol] = 'http'
    if defined?(ActionMailer)
      ActionMailer::Base.default_url_options = { host: 'localhost', protocol: 'http' }
      ActionMailer::Base.delivery_method = :test
    end
    Devise.mailer.default_url_options = { host: 'localhost', protocol: 'http' } if defined?(Devise)
  end

  # System specs WITHOUT JS => fast rack_test
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  # System specs WITH JS => Selenium + headless Chrome
  config.before(:each, :js, type: :system) do
    driven_by :selenium_chrome_headless
    # start fresh so things like cookie banners appear
    begin
      page.driver.browser.manage.delete_all_cookies
    rescue StandardError
      # rack_test doesn't implement this – ignore
    end
    Capybara.reset_sessions!
    # Selenium reutiliza la misma ventana entre ejemplos y Capybara no la
    # restaura, así que el tamaño que dejaba un spec se lo comía el siguiente.
    page.current_window.resize_to(*SYSTEM_SPEC_WINDOW_SIZE)
    # La emulación CDP vive en el navegador, no en la sesión: ni
    # `reset_sessions!` ni `driven_by` la limpian. Medido: 17 ms de referencia,
    # 65 ms con throttle 6x, y 63 ms en el ejemplo SIGUIENTE que nunca lo pidió.
    # Un spec que estrangula la CPU para simular lentitud puede así contagiar al
    # resto de la suite y hacer fallar un ejemplo cualquiera. Se restablece al
    # ENTRAR a cada ejemplo, no al salir del que lo puso: así un cleanup que
    # falle en otro spec no puede contaminar a los demás.
    SystemSpecCdpEmulation.reset!(page.driver.browser)
  end

  # If a JS/system spec fails, dump the HTML and a screenshot for easier debugging
  config.after(:each, :js, type: :system) do |example|
    if example.exception
      # Always safe; writes HTML to tmp/capybara
      save_page
      begin
        save_screenshot
      rescue StandardError
        # rack_test and dead sessions can't screenshot – ignore
      end
      # If you prefer opening the browser locally and have 'launchy' installed, uncomment:
      # save_and_open_page
    end
  end
end

# --- RSwag stability for write-heavy request examples ---
RSpec.configure do |config|
  # Para ejemplos de rswag (definidos por metadata :rswag o path en spec/requests/api/v1/* con swagger_helper),
  # desactivar transacción automática y limpiar BD manualmente para evitar PG::InFailedSqlTransaction.
  config.around(:each, :rswag) do |example|
    prev = defined?(Bullet) ? Bullet.enabled? : nil
    Bullet.enable = false if defined?(Bullet)

    ActiveRecord::Base.connection.begin_transaction(joinable: false)
    begin
      example.run
    ensure
      # rollback para limpiar todo lo creado en el ejemplo
      ActiveRecord::Base.connection.rollback_transaction
      Bullet.enable = prev if defined?(Bullet) && !prev.nil?
    end
  end
end

# Shoulda Matchers
Shoulda::Matchers.configure do |shoulda|
  shoulda.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
