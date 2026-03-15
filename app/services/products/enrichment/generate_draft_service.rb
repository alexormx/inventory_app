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

      DEFAULT_MODEL = "gpt-4o-mini"

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
      end

      def parse_response(response)
        content = response.dig("choices", 0, "message", "content")
        raise GenerationError, "Empty response from OpenAI" if content.blank?

        parsed = JSON.parse(content)

        unless parsed.is_a?(Hash) && parsed["description_es"].present?
          raise GenerationError, "Invalid response structure: missing 'description_es'"
        end

        parsed
      rescue JSON::ParserError => e
        raise GenerationError, "Failed to parse OpenAI JSON response: #{e.message}"
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
