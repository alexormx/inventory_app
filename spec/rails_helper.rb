require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?

require "rspec/rails"
require "capybara/rspec"
require "selenium-webdriver"

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# --- Capybara + Selenium setup ---
Capybara.default_max_wait_time = 5

Capybara.register_driver :selenium_chrome_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--disable-gpu")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--disable-background-networking")
  options.add_argument("--disable-software-rasterizer")
  options.add_argument("--disable-dev-tools")
  options.add_argument("--disable-features=VizDisplayCompositor")
  options.add_argument("--disable-features=IsolateOrigins,site-per-process")
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

RSpec.configure do |config|
  # Fixtures / Rails noise
  config.fixture_paths = [Rails.root.join("spec/fixtures")]
  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!

  # Helpers
  config.include Rails.application.routes.url_helpers
  config.include FactoryBot::Syntax::Methods
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include Devise::Test::IntegrationHelpers, type: :request

  # Default URL options (for *_url helpers & Devise mailers)
  config.before(:suite) do
    Rails.application.routes.default_url_options[:host] = "localhost"
    Rails.application.routes.default_url_options[:protocol] = "http"
    if defined?(ActionMailer)
      ActionMailer::Base.default_url_options = { host: "localhost", protocol: "http" }
      ActionMailer::Base.delivery_method = :test
    end
    if defined?(Devise)
      Devise.mailer.default_url_options = { host: "localhost", protocol: "http" }
    end
  end

  # System specs WITHOUT JS => fast rack_test
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  # System specs WITH JS => Selenium + headless Chrome
  config.before(:each, type: :system, js: true) do
    driven_by :selenium_chrome_headless
    # start fresh so things like cookie banners appear
    begin
      page.driver.browser.manage.delete_all_cookies
    rescue StandardError
      # rack_test doesn't implement this – ignore
    end
    Capybara.reset_sessions!
  end

  # If a JS/system spec fails, dump the HTML for easier debugging
  config.after(:each, type: :system, js: true) do |example|
    save_and_open_page if example.exception
  end
end

# Shoulda Matchers
Shoulda::Matchers.configure do |shoulda|
  shoulda.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end