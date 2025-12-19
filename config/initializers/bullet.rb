# frozen_string_literal: true

# Bullet gem configuration for N+1 query detection
if defined?(Bullet)
  # Solo habilitar en desarrollo - en test causa problemas con transacciones
  Bullet.enable = Rails.env.development?

  # Development environment configuration
  if Rails.env.development?
    # Show alerts in the browser
    Bullet.alert = true

    # Log to Rails log
    Bullet.rails_logger = true

    # Console output
    Bullet.console = true

    # Add Bullet footer to pages
    Bullet.add_footer = true

    # Detect N+1 queries
    Bullet.n_plus_one_query_enable = true

    # Detect unused eager loading
    Bullet.unused_eager_loading_enable = true

    # Detect counter cache that should be used
    Bullet.counter_cache_enable = true
  end
end
