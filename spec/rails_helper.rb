require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'

# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?

require 'rspec/rails'
require 'selenium-webdriver'
require 'capybara/rspec'

# Toggle: run system specs only when explicitly requested
RUN_SYSTEM_SPECS = ENV['RUN_SYSTEM_SPECS'] == '1'

# Ensure database migrations are applied before running tests
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

# Load support files (helpers, shared contexts, etc.)
Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |shoulda|
  shoulda.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

RSpec.configure do |config|
  # Fixture & DB settings
  config.fixture_paths = [Rails.root.join('spec/fixtures')]
  config.use_transactional_fixtures = true

  # Helpers
  config.include FactoryBot::Syntax::Methods
  config.include Devise::Test::ControllerHelpers, type: :controller
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system

  # JSON helper (defined in spec/support/json_helpers.rb)
  config.include JsonHelpers, type: :controller if defined?(JsonHelpers)
  config.include JsonHelpers, type: :request    if defined?(JsonHelpers)

  # System specs (off by default)
  if RUN_SYSTEM_SPECS
    Capybara.register_driver :selenium do |app|
      options = Selenium::WebDriver::Chrome::Options.new
      options.add_argument('--disable-gpu')
      options.add_argument('--disable-software-rasterizer')
      options.add_argument('--disable-dev-shm-usage')
      options.add_argument('--disable-dev-tools')
      options.add_argument('--disable-features=VizDisplayCompositor')
      options.add_argument('--disable-features=IsolateOrigins,site-per-process')
      options.add_argument('--no-sandbox')
      options.add_argument('--headless=new')
      options.add_argument('--disable-background-networking')
      Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
    end
    Capybara.javascript_driver = :selenium

    # Open page on failing system spec (only when system specs are enabled)
    config.after(:each, type: :system) do |example|
      save_and_open_page if example.exception
    end
  else
    # Skip all system specs unless explicitly enabled
    config.filter_run_excluding type: :system
  end

  # Backtrace cleanup
  config.filter_rails_from_backtrace!

  # Infer spec types from file locations (enabled by rspec-rails)
  # config.infer_spec_type_from_file_location!
end