# frozen_string_literal: true

module Products
  module Enrichment
    # Orchestrates the full generation flow:
    # 1. Build context from Product
    # 2. Build prompt from context
    # 3. Call OpenAI API
    # 4. Parse and normalize response
    # 5. Persist results in ProductDescriptionDraft
    class GenerateDraftService
      class GenerationError < StandardError; end
      class RateLimitError < GenerationError; end

      DEFAULT_MODEL = "gpt-4o-mini"

      MAX_RETRIES     = 3
      BASE_WAIT_SECS  = 5

      # Cost per 1M tokens (USD cents) — gpt-4o-mini pricing as of 2025
      COST_INPUT_PER_M  = 15   # $0.15 / 1M input tokens  → 15 cents
      COST_OUTPUT_PER_M = 60   # $0.60 / 1M output tokens → 60 cents

      def initialize(draft, model: nil)
        @draft = draft
        @product = draft.product
        @model = model || DEFAULT_MODEL
      end

      def call
        @draft.update!(status: :generating)

        context = BuildContextService.new(@product).call
        prompt  = BuildPromptService.new(context).call

        response = call_openai(prompt)
        parsed   = parse_response(response)

        template = @product.attribute_template
        normalized_attrs = NormalizeAttributesService.new(parsed["attributes"], template).call

        usage = response.dig("usage") || {}

        @draft.update!(
          status:              :draft_generated,
          draft_content:       parsed["description_es"],
          draft_attributes:    normalized_attrs,
          structured_output:   parsed,
          warnings:            parsed["warnings"] || [],
          confidence_score:    parsed["confidence_score"],
          source_snapshot:     context,
          prompt_used:         prompt[:user],
          prompt_version:      prompt[:version],
          ai_provider:         "openai",
          ai_model:            @model,
          tokens_input:        usage["prompt_tokens"],
          tokens_output:       usage["completion_tokens"],
          estimated_cost_cents: estimate_cost(usage),
          generated_at:        Time.current
        )

        @draft
      rescue RateLimitError => e
        @draft.update!(
          status:        :failed,
          error_message: "#{e.class}: #{e.message}",
          generated_at:  Time.current
        )
        raise # re-raise as-is so job retries with longer waits
      rescue StandardError => e
        @draft.update!(
          status:        :failed,
          error_message: "#{e.class}: #{e.message}",
          generated_at:  Time.current
        )
        raise GenerationError, "Failed to generate draft for product #{@product.id}: #{e.message}"
      end

      private

      def call_openai(prompt)
        client = OpenAI::Client.new
        retries = 0

        begin
          client.chat(
            parameters: {
              model:       @model,
              messages:    [
                { role: "system", content: prompt[:system] },
                { role: "user",   content: prompt[:user] }
              ],
              temperature:     0.4,
              response_format: { type: "json_object" },
              max_tokens:      2000
            }
          )
        rescue Faraday::TooManyRequestsError => e
          retries += 1
          if retries <= MAX_RETRIES
            wait_time = BASE_WAIT_SECS * (2**(retries - 1)) # 5s, 10s, 20s
            Rails.logger.warn("[Enrichment] OpenAI 429 rate limit for product #{@product.id}, retry #{retries}/#{MAX_RETRIES} in #{wait_time}s")
            sleep(wait_time)
            retry
          end
          raise RateLimitError, "OpenAI rate limit exceeded after #{MAX_RETRIES} retries: #{e.message}"
        end
      end

      def parse_response(response)
        content = response.dig("choices", 0, "message", "content")
        raise GenerationError, "Empty response from OpenAI" if content.blank?

        parsed = JSON.parse(content)

        unless parsed.is_a?(Hash) && parsed["description_es"].present?
          raise GenerationError, "Invalid response structure: missing 'description_es'"
        end

        unless structured_description?(parsed["description_es"])
          raise GenerationError, "Invalid response structure: 'description_es' must include the required structured sections"
        end

        parsed
      rescue JSON::ParserError => e
        raise GenerationError, "Failed to parse OpenAI JSON response: #{e.message}"
      end

      def structured_description?(description)
        return false if description.blank?

        normalized = description.to_s.strip
        required_sections = [
          "Resumen:",
          "Ficha del modelo:",
          "Puntos destacados:",
          "Historia y contexto:",
          "Cierre:"
        ]

        return false unless required_sections.all? { |section| normalized.include?(section) }
        return false if normalized.length < 180

        bullet_count = normalized.scan(/^\s*[-•*]\s+/).size
        bullet_count >= 3
      end

      def estimate_cost(usage)
        input_tokens  = usage["prompt_tokens"] || 0
        output_tokens = usage["completion_tokens"] || 0

        input_cost  = (input_tokens.to_f / 1_000_000) * COST_INPUT_PER_M
        output_cost = (output_tokens.to_f / 1_000_000) * COST_OUTPUT_PER_M

        ((input_cost + output_cost) * 100).ceil # cents
      end
    end
  end
end
