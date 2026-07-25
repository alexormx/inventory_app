# frozen_string_literal: true

# OpenAI API client configuration for product enrichment
# Set OPENAI_API_KEY in env vars or Rails credentials

OpenAI.configure do |config|
  api_key = ENV.fetch("OPENAI_API_KEY", nil)
  api_key = Rails.application.credentials.dig(:openai, :api_key) if api_key.blank?

  config.access_token = api_key
  config.request_timeout = 60
end
