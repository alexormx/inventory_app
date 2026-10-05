# frozen_string_literal: true

module Collectibles
  # Esquema estricto (Structured Outputs) de la respuesta. En modo estricto todo
  # campo va en `required` y lo opcional se expresa como null.
  module AiLookupSchema
    LISTING = {
      type: 'object', additionalProperties: false,
      required: %w[title price price_original url sold],
      properties: {
        title: { type: 'string' },
        price: { type: 'number' },
        price_original: { type: 'string' },
        url: { type: 'string' },
        sold: { type: 'boolean' }
      }
    }.freeze

    def self.market(currency)
      {
        anyOf: [
          {
            type: 'object', additionalProperties: false,
            required: %w[min max currency listings],
            properties: {
              min: { type: 'number' }, max: { type: 'number' },
              currency: { type: 'string', enum: [currency] },
              listings: { type: 'array', items: LISTING }
            }
          },
          { type: 'null' }
        ]
      }
    end

    NULLABLE_STRING = { type: %w[string null] }.freeze

    CANDIDATE = {
      type: 'object', additionalProperties: false,
      required: %w[product_name brand model_code reason confidence],
      properties: {
        product_name: { type: 'string' }, brand: NULLABLE_STRING, model_code: NULLABLE_STRING,
        reason: { type: 'string' }, confidence: { type: 'number' }
      }
    }.freeze

    SCHEMA = {
      type: 'object', additionalProperties: false,
      required: %w[identification launch_date rarity prices_mx prices_world suggested candidates warnings],
      properties: {
        identification: {
          type: 'object', additionalProperties: false,
          required: %w[product_name brand series model_code scale year_or_edition confidence notes],
          properties: {
            product_name: { type: 'string' }, brand: NULLABLE_STRING, series: NULLABLE_STRING,
            model_code: NULLABLE_STRING, scale: NULLABLE_STRING, year_or_edition: NULLABLE_STRING,
            confidence: { type: 'number' }, notes: NULLABLE_STRING
          }
        },
        launch_date: {
          type: 'object', additionalProperties: false, required: %w[value source_url],
          properties: { value: NULLABLE_STRING, source_url: NULLABLE_STRING }
        },
        rarity: {
          type: 'object', additionalProperties: false, required: %w[level reasons],
          properties: {
            level: { type: %w[string null], enum: ['comun', 'poco_comun', 'rara', 'muy_rara', nil] },
            reasons: { type: 'array', items: { type: 'string' } }
          }
        },
        prices_mx: market('MXN'),
        prices_world: market('USD'),
        suggested: {
          type: 'object', additionalProperties: false, required: %w[category description_es],
          properties: { category: NULLABLE_STRING, description_es: NULLABLE_STRING }
        },
        candidates: { type: 'array', items: CANDIDATE },
        warnings: { type: 'array', items: { type: 'string' } }
      }
    }.freeze
  end
end
