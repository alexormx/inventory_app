# frozen_string_literal: true

source 'https://rubygems.org'

# ✅ Define Ruby version
ruby '3.2.3'

# ✅ Core Rails Framework
gem 'rails', '~> 8.0.1'

# ✅ Database
gem 'pg', '~> 1.1' # PostgreSQL as the database for Active Record

# ✅ Web Server
gem 'puma', '>= 5.0' # Puma web server

# ✅ Asset Pipeline & Frontend
# gem "propshaft"  # Disabled to use Sprockets + Sass pipeline for SCSS

# ✅ Hotwire (Turbo + Stimulus)
gem 'importmap-rails' # ESM import maps for JavaScript
gem 'jsbundling-rails' # JavaScript bundling with esbuild
gem 'stimulus-rails' # JavaScript framework
gem 'turbo-rails' # SPA-like page accelerator

# ✅ JSON API Support
gem 'jbuilder' # Build JSON APIs

# ✅ Authentication
gem 'devise', '~> 4.9' # User authentication and session handling

# ✅ Caching & Performance
gem 'bootsnap', require: false # Improves boot times through caching
gem 'solid_cable' # WebSocket connection for ActionCable
gem 'solid_cache' # Database-backed caching
gem 'solid_queue' # Background job system

# ✅ Deployment & Production Enhancements
gem 'kamal', require: false # Deploy Rails app as a Docker container
gem 'thruster', require: false # HTTP caching/compression with Puma

# ✅ Faker for Testing & Seeding
gem 'faker'

# ✅ Timezone Handling (Windows-specific)
gem 'tzinfo-data', platforms: %i[mingw jruby]

# ✅ Image Processing (Commented Out but Available)
# gem "image_processing", "~> 1.2"  # ActiveStorage image transformations

# ✅ Internationalization for Devise
gem 'devise-i18n', '~> 1.12' # Devise internationalization

# ✅ Bootstrap framework for styling
gem 'bootstrap', '~> 5.3.3'
gem 'friendly_id', '~> 5.5'
gem 'image_processing', '~> 1.2'
gem 'mini_magick'
gem 'redis', '~> 4.8' # Redis for caching and background jobs
gem 'sassc-rails'
gem 'sitemap_generator'
gem 'sprockets-rails'

# ✅ Paginación
gem 'kaminari'

# ✅ Additional Gems for geolocalization
gem 'geocoder'

# ✅ API Documentation
gem 'rswag-api'
gem 'rswag-ui'

# (Removed XLSX export gems; CSV remains via stdlib)

# 🔹 **Development & Testing Group**
group :development, :test do
  # Debugging: habilitar en MRI y entornos Windows (mingw/mswin)
  gem 'brakeman', require: false # Security vulnerability scanner
  gem 'bullet' # N+1 query detection
  gem 'debug', platforms: %i[mri mingw x64_mingw mswin], require: 'debug/prelude'
  gem 'dotenv-rails' # Manage environment variables securely
  gem 'factory_bot_rails' # Define test data
  gem 'rubocop', require: false # Ruby static code analyzer
  gem 'rubocop-rails', require: false # Ruby style guide
  gem 'rubocop-rails-omakase', require: false # Omakase Ruby style guide
  gem 'rubocop-rspec', require: false # RSpec style guide
  # gem "sqlite3", "~> 2.2"  # Disabled in favor of PostgreSQL for consistency
end

# 🔹 **Development Group**
group :development do
  gem 'foreman', require: false # Procfile runner for bin/dev
  gem 'letter_opener' # Preview email in the browser instead of sending
  gem 'overcommit' # Git hooks for code quality
  gem 'web-console' # Rails console in browser for debugging
end

# 🔹 **Testing Group**
group :test do
  gem 'capybara' # Feature test framework (UI testing)
  gem 'launchy' # Open HTML pages in the default browser
  gem 'rails-controller-testing', '1.0.5' # Helps test controllers
  gem 'rspec-rails' # RSpec testing framework
  gem 'selenium-webdriver' # Browser automation for system tests
  gem 'shoulda-matchers', '~> 5.0' # Simplifies model testing
  gem 'rswag-specs' # API documentation specs
end

# 🔹 **Production Group*
group :production do
  # images storage in aws
  gem 'aws-sdk-s3', '1.114.0', require: false
end
