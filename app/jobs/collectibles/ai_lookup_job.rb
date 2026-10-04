# frozen_string_literal: true

module Collectibles
  # Corre AiLookupService en el worker y deja la búsqueda en done o failed.
  # Sólo el 429 se reintenta (5 s, 10 s, 20 s) re-encolando, no con sleep: el
  # worker tiene dos hilos y una espera dormida bloquearía uno.
  class AiLookupJob < ApplicationJob
    queue_as :default

    retry_on Collectibles::AiLookupService::RateLimitError,
             wait: ->(executions) { 5 * (2**(executions - 1)) },
             attempts: 4 do |job, _error|
      lookup = Collectibles::AiLookup.find_by(id: job.arguments.first)
      lookup&.update!(status: :failed, finished_at: Time.current,
                      error_message: 'OpenAI está saturado; intenta de nuevo en unos minutos.')
    end

    discard_on ActiveRecord::RecordNotFound

    def perform(lookup_id)
      lookup = Collectibles::AiLookup.find(lookup_id)
      return if lookup.done? || lookup.failed?

      lookup.update!(status: :running, started_at: lookup.started_at || Time.current,
                     ai_model: Collectibles::AiLookupService::MODEL)
      result = Collectibles::AiLookupService.new(lookup).call
      lookup.update!(status: :done, result: result.data, tokens_input: result.tokens_input,
                     tokens_output: result.tokens_output, web_search_calls: result.web_search_calls,
                     estimated_cost_cents: result.cost_cents, finished_at: Time.current)
    rescue Collectibles::AiLookupService::RateLimitError
      raise
    rescue Collectibles::AiLookupService::Error, Faraday::Error => e
      lookup.update!(status: :failed, finished_at: Time.current,
                     error_message: "No se pudo completar la búsqueda: #{e.message}".truncate(500))
    end
  end
end
