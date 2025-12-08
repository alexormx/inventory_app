# frozen_string_literal: true

# Bullet gem configuration for N+1 query detection
if defined?(Bullet)
  Bullet.enable = true

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

  # Test environment configuration
  if Rails.env.test?
    # Raise errors to catch N+1 queries in specs
    Bullet.raise = true

    # Log to test log
    Bullet.rails_logger = true

    # Detect N+1 queries (most important check)
    Bullet.n_plus_one_query_enable = true

    # Disable unused eager loading detection in tests (causes false positives
    # because test requests often don't render full HTML where associations are used)
    Bullet.unused_eager_loading_enable = false
  end
end
