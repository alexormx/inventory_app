source "https://rubygems.org"

# ✅ Define Ruby version
ruby "3.2.3"

# ✅ Core Rails Framework
gem "rails", "~> 8.0.1"

# ✅ Database
gem "pg", "~> 1.1"  # PostgreSQL as the database for Active Record

# ✅ Web Server
gem "puma", ">= 5.0"  # Puma web server

# ✅ Asset Pipeline & Frontend
gem "propshaft"  # Modern asset pipeline for Rails

# ✅ Hotwire (Turbo + Stimulus)
gem "importmap-rails"  # ESM import maps for JavaScript
gem "jsbundling-rails"  # JavaScript bundling with esbuild
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
gem "tzinfo-data", platforms: %i[mingw jruby]

# ✅ Image Processing (Commented Out but Available)
# gem "image_processing", "~> 1.2"  # ActiveStorage image transformations

# ✅ Internationalization for Devise
gem "devise-i18n", "~> 1.12"  # Devise internationalization

# ✅ Bootstrap framework for styling
gem "bootstrap", "~> 5.3.3"
gem "sassc-rails"
gem "sprockets-rails"
gem "image_processing", "~> 1.2"
gem "mini_magick"
gem "redis", "~> 4.8" # Redis for caching and background jobs
gem "sitemap_generator"
gem "friendly_id", "~> 5.5"

# ✅ Paginación
gem "kaminari"

# ✅ Additional Gems for geolocalization
gem 'geocoder'

# (Removed XLSX export gems; CSV remains via stdlib)


# 🔹 **Development & Testing Group**
group :development, :test do
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"  # Debugging
  gem "brakeman", require: false  # Security vulnerability scanner
  gem "rubocop", require: false  # Ruby static code analyzer
  gem "rubocop-rails", require: false  # Ruby style guide
  gem "rubocop-rspec", require: false  # RSpec style guide
  gem "rubocop-rails-omakase", require: false  # Omakase Ruby style guide
  gem "dotenv-rails"  # Manage environment variables securely
  gem "factory_bot_rails"  # Define test data
end

# 🔹 **Development Group**
group :development do
  gem "overcommit" # Git hooks for code quality
  gem "web-console"  # Rails console in browser for debugging
  gem "letter_opener" # Preview email in the browser instead of sending
end

# 🔹 **Testing Group**
group :test do
  gem "capybara"  # Feature test framework (UI testing)
  gem "launchy" # Open HTML pages in the default browser
  gem "selenium-webdriver"  # Browser automation for system tests
  gem "rails-controller-testing", "1.0.5"  # Helps test controllers
  gem "rspec-rails"  # RSpec testing framework
  gem "shoulda-matchers", "~> 5.0"  # Simplifies model testing
  gem "sqlite3", "~> 2.2"
end


# 🔹 **Production Group*
group :production do
  # images storage in aws
  gem "aws-sdk-s3", "1.114.0", require: false
end
