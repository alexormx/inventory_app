source "https://rubygems.org"

ruby "3.2.9"

# Core
gem "rails", "~> 8.0.1"
gem "puma", ">= 5.0"
gem "pg", "~> 1.1"

# Assets (Propshaft)
gem "propshaft"

# Hotwire
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"


# API / utils
gem "jbuilder"
gem "friendly_id", "~> 5.5"
gem "kaminari"
gem "geocoder"
gem "sitemap_generator"

# Auth
gem "devise", "~> 4.9"
gem "devise-i18n", "~> 1.13"

# Caching / Jobs / Cable (Rails 8 stack)
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"
gem "bootsnap", require: false

# ActiveStorage image variants (opcional)
# Usa ruby-vips (rápido) → requiere libvips en el sistema (Aptfile).
# Si NO generas variantes, comenta estas dos.
gem "image_processing", "~> 1.2"
gem "ruby-vips"

# Redis (solo si lo usas realmente: cache_store, ActionCable redis, etc.)
# Con solid_* ya no es obligatorio. Si no lo usas, quítalo.
# gem "redis", "~> 4.8"

# Windows tz
gem "tzinfo-data", platforms: %i[mingw jruby]

group :development, :test do
  gem "dotenv-rails"
  gem "factory_bot_rails"
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  # Herramientas de calidad (solo desarrollo en la práctica)
  gem "brakeman", require: false
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
  gem "rubocop-rspec", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "overcommit", require: false
  gem "web-console"
  gem "letter_opener"
  gem "kamal", require: false
  gem "faker"
end

group :test do
  gem "capybara"
  gem "launchy"
  gem "selenium-webdriver"
  gem "rails-controller-testing", "1.0.5"
  gem "rspec-rails"
  gem "shoulda-matchers", "~> 5.0"
  gem "sqlite3", "~> 2.2"
end

group :production do
  gem "aws-sdk-s3", "1.114.0", require: false
end
gem "cssbundling-rails", "~> 1.4"
