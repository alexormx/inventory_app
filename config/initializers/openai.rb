# frozen_string_literal: true

# OpenAI API client configuration for product enrichment
# Set OPENAI_API_KEY in env vars or Rails credentials

OpenAI.configure do |config|
  config.access_token = ENV.fetch("OPENAI_API_KEY", Rails.application.credentials.dig(:openai, :api_key))
  config.request_timeout = 60
end
