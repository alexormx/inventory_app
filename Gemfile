source "https://rubygems.org"

# ✅ Define Ruby version
ruby "3.2.2"

# ✅ Core Rails Framework
gem "rails", "~> 8.0.1"

# ✅ Database
gem "pg", "~> 1.1"  # PostgreSQL as the database for Active Record

# ✅ Web Server
gem "puma", ">= 5.0"  # Puma web server

# ✅ Asset Pipeline & Frontend
gem "propshaft"  # Modern asset pipeline for Rails
gem "tailwindcss-rails"  # Tailwind CSS for styling

# ✅ Hotwire (Turbo + Stimulus)
gem "importmap-rails"  # ESM import maps for JavaScript
gem "turbo-rails"  # SPA-like page accelerator
gem "stimulus-rails"  # JavaScript framework

# ✅ JSON API Support
gem "jbuilder"  # Build JSON APIs

# ✅ Authentication
gem "devise", "~> 4.9"  # User authentication and session handling

# ✅ Caching & Performance
gem "solid_cache"  # Database-backed caching
gem "solid_queue"  # Background job system
gem "solid_cable"  # WebSocket connection for ActionCable
gem "bootsnap", require: false  # Improves boot times through caching

# ✅ Deployment & Production Enhancements
gem "kamal", require: false  # Deploy Rails app as a Docker container
gem "thruster", require: false  # HTTP caching/compression with Puma

# ✅ Faker for Testing & Seeding
gem "faker"

# ✅ Timezone Handling (Windows-specific)
gem "tzinfo-data", platforms: %i[windows jruby]

# ✅ Image Processing (Commented Out but Available)
# gem "image_processing", "~> 1.2"  # ActiveStorage image transformations

# 🔹 **Development & Testing Group**
group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"  # Debugging
  gem "brakeman", require: false  # Security vulnerability scanner
  gem "rubocop-rails-omakase", require: false  # Omakase Ruby style guide
  gem "dotenv-rails"  # Manage environment variables securely
end

# 🔹 **Development Group**
group :development do
  gem "web-console"  # Rails console in browser for debugging
end

# 🔹 **Testing Group**
group :test do
  gem "capybara"  # Feature test framework (UI testing)
  gem "selenium-webdriver"  # Browser automation for system tests
  gem "webdrivers", "5.0.0"  # Keeps browser drivers up-to-date
  gem "rails-controller-testing", "1.0.5"  # Helps test controllers
  gem "rspec-rails"  # RSpec testing framework
  gem "shoulda-matchers", "~> 5.0"  # Simplifies model testing
end
