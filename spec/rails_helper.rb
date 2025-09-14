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

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# --- Capybara + Selenium setup ---
Capybara.default_max_wait_time = 7

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
  driver_path = '/usr/lib/chromium-browser/chromedriver'
  service = Selenium::WebDriver::Service.chrome(
    path: driver_path
  )

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options, service: service)
end

RSpec.configure do |config|
  # Fixtures / Rails noise
  config.fixture_paths = Rails.root.join('spec/fixtures')
  config.use_transactional_fixtures = true
  config.filter_rails_from_backtrace!

  # Skip system specs (and therefore Selenium/Chromedriver) for this stabilization branch
  # This can be reverted later by removing this filter.
  config.filter_run_excluding type: :system

  # Helpers
  config.include Rails.application.routes.url_helpers
  config.include FactoryBot::Syntax::Methods
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include ActiveSupport::Testing::TimeHelpers

  # Default URL options (for *_url helpers & Devise mailers)
  config.before(:suite) do
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
  end

  # If a JS/system spec fails, dump the HTML for easier debugging
  config.after(:each, :js, type: :system) do |example|
    if example.exception
      # Always safe; writes HTML to tmp/capybara
      save_page
      # If you prefer opening the browser locally and have 'launchy' installed, uncomment:
      # save_and_open_page
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