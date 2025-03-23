# Force Redis to accept self-signed SSL certs (Heroku-compatible)
if Rails.env.production?
  ActionCable.server.config.cable = { adapter: 'redis', url: ENV['REDIS_URL'], ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE } }
end
# Configure Redis for ActionCable 