# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?

require 'rspec/rails'
require 'selenium-webdriver'
require 'webdrivers'
require 'capybara/rspec'

# Ensure database migrations are applied before running tests
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # Define fixture paths
  config.fixture_paths = [Rails.root.join('spec/fixtures')]
  config.use_transactional_fixtures = true

  config.filter_rails_from_backtrace!

  # Shoulda Matchers Configuration
  Shoulda::Matchers.configure do |shoulda|
    shoulda.integrate do |with|
      with.test_framework :rspec
      with.library :rails
    end
  end


  # ✅ **SET CHROMEDRIVER PATH & VERSION BEFORE REGISTERING DRIVER**
  Webdrivers::Chromedriver.required_version = '134.0.6998.0'
  if File.exist?("/usr/bin/chromedriver")
    Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver"
  else
    config.filter_run_excluding type: :system
  end

  # ✅ **REGISTER SELENIUM DRIVER**
  Capybara.register_driver :selenium do |app|
    options = Selenium::WebDriver::Chrome::Options.new

    # ✅ Essential flags to disable GPU errors
    options.add_argument('--disable-gpu')
    options.add_argument('--disable-software-rasterizer')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-dev-tools')
    options.add_argument('--disable-features=VizDisplayCompositor') # Helps prevent GPU rendering issues
    options.add_argument('--disable-features=IsolateOrigins,site-per-process')

    # ✅ Keep these for stability in WSL & Docker
    options.add_argument('--no-sandbox')
    options.add_argument('--headless=new') # Use updated headless mode
    options.add_argument('--disable-background-networking')

    Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
  end

  Capybara.javascript_driver = :selenium

  # FactoryBot Configuration
  config.include FactoryBot::Syntax::Methods

  # Include Devise test helpers
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include Devise::Test::IntegrationHelpers, type: :request

  # Automatically open screenshot on test failure (Capybara & Launchy)
  config.after(:each, type: :system) do |example|
    if example.exception
      save_and_open_page
    end
  end

end
