# frozen_string_literal: true

module Products
  module Enrichment
    # Orchestrates the full generation flow:
    # 1. Build context from Product
    # 2. Build prompt from context
    # 3. Call OpenAI (gpt-4.1-mini) with the prompt and up to 3 product photos, strict JSON schema
    # 4. Parse and normalize response
    # 5. Persist results in ProductDescriptionDraft
    class GenerateDraftService
      class GenerationError < StandardError; end
      # 429: el job reintenta con espera, sin dormir el hilo del worker.
      class RateLimitError < GenerationError; end
      # Timeout, conexión o 5xx: el job reintenta.
      class TransientError < GenerationError; end
      # JSON roto o descripción que no pasa las reglas: el job reintenta una vez.
      class InvalidResponseError < GenerationError; end

      BANNED_SECTION_HEADINGS = [
        "Resumen:",
        "Ficha del modelo:",
        "Puntos destacados:",
        "Historia y contexto:",
        "Cierre:"
      ].freeze

      DEFAULT_MODEL = "gpt-4.1-mini"
      REQUEST_TIMEOUT = 90

      # USD por 1M tokens, gpt-4.1-mini, página de precios de OpenAI verificada el 2026-10-05.
      COST_INPUT_PER_M_USD = 0.40
      COST_OUTPUT_PER_M_USD = 1.60

      def initialize(draft, model: nil)
        @draft = draft
        @product = draft.product
        @model = model || DEFAULT_MODEL
      end

      def call
        @draft.update!(status: :generating)

        context = Products::Enrichment::BuildContextService.new(@product).call
        prompt  = Products::Enrichment::BuildPromptService.new(context).call

        photos   = Products::Enrichment::PhotoSourceService.new(@product).call
        response = call_openai(prompt, photos.jpegs)
        parsed   = parse_response(response)
        parsed["warnings"] = Array(parsed["warnings"]) + photos.warnings

        template = @product.attribute_template
        normalized_attrs = Products::Enrichment::NormalizeAttributesService.new(parsed["attributes"], template).call

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
      rescue GenerationError => e
        mark_failed(e)
        raise
      rescue StandardError => e
        mark_failed(e)
        raise GenerationError, "Failed to generate draft for product #{@product.id}: #{e.message}"
      end

      private

      def mark_failed(error)
        @draft.update!(status: :failed, error_message: "#{error.class}: #{error.message}", generated_at: Time.current)
      end

      def call_openai(prompt, jpegs)
        OpenAI::Client.new(request_timeout: REQUEST_TIMEOUT).chat(
          parameters: {
            model:           @model,
            messages:        [
              { role: "system", content: prompt[:system] },
              { role: "user",   content: user_content(prompt[:user], jpegs) }
            ],
            temperature:     0.4,
            response_format: { type: "json_schema",
                               json_schema: { name: "product_enrichment", strict: true,
                                              schema: Products::Enrichment::ResponseSchema.for(@product.attribute_template) } },
            max_tokens:      2000
          }
        )
      rescue Faraday::TooManyRequestsError => e
        raise RateLimitError, "OpenAI está saturado (429): #{e.message}"
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed, Faraday::ServerError => e
        raise TransientError, "OpenAI no respondió: #{e.message}"
      end

      # Sin fotos el mensaje es sólo texto; con fotos, cada una va etiquetada.
      def user_content(text, jpegs)
        return text if jpegs.empty?

        [{ type: "text", text: text }] + jpegs.each_with_index.flat_map do |jpeg, index|
          [{ type: "text", text: "Foto #{index + 1} del producto" },
           { type: "image_url", image_url: { url: "data:image/jpeg;base64,#{Base64.strict_encode64(jpeg)}", detail: "high" } }]
        end
      end

      def parse_response(response)
        content = response.dig("choices", 0, "message", "content")
        raise InvalidResponseError, "Empty response from OpenAI" if content.blank?

        parsed = JSON.parse(content)

        unless parsed.is_a?(Hash) && parsed["description_es"].present?
          raise InvalidResponseError, "Invalid response structure: missing 'description_es'"
        end

        parsed["description_es"] = sanitize_description(parsed["description_es"])
        scrub_identifiers(parsed)

        unless natural_description?(parsed["description_es"])
          raise InvalidResponseError, "Invalid response structure: 'description_es' must be natural copy without headings or null values"
        end

        parsed
      rescue JSON::ParserError => e
        raise InvalidResponseError, "Failed to parse OpenAI JSON response: #{e.message}"
      end

      # Aunque el prompt lo prohíbe, la IA a veces copia el SKU o el código de
      # barras como característica; aquí se quitan antes de guardar el borrador.
      def scrub_identifiers(parsed)
        scrubber = Products::Enrichment::ScrubIdentifiersService.new(@product)
        parsed["description_es"] = scrubber.clean_text(parsed["description_es"])
        parsed["highlights"] = scrubber.clean_list(parsed["highlights"])
        parsed["seo_keywords"] = scrubber.clean_list(parsed["seo_keywords"])
        return unless scrubber.removed?

        parsed["warnings"] = Array(parsed["warnings"]) +
                             ["Se quitaron identificadores internos (SKU, códigos de proveedor o de barras) del texto generado."]
      end

      def sanitize_description(description)
        description.to_s
                   .gsub(/\r\n?/, "\n")
                   .lines
                   .map(&:rstrip)
                   .join("\n")
                   .gsub(/[ \t]+\n/, "\n")
                   .gsub(/\n{3,}/, "\n\n")
                   .strip
      end

      def natural_description?(description)
        return false if description.blank?

        normalized = description.to_s.strip
        normalized_downcase = normalized.downcase
        paragraphs = normalized.split(/\n{2,}/).map(&:strip).reject(&:blank?)
        bullet_count = normalized.scan(/^\s*[-•*]\s+/).size

        # El estilo objetivo es corto (1 o 2 párrafos), así que un solo párrafo
        # factual es válido; sólo rechazamos textos triviales o vacíos.
        return false if normalized.length < 100
        return false if paragraphs.empty?
        return false if bullet_count >= 2
        return false if BANNED_SECTION_HEADINGS.any? { |section| normalized_downcase.include?(section.downcase) }
        return false if normalized_downcase.match?(/(^|[^a-záéíóúñ])null([^a-záéíóúñ]|$)/i)

        true
      end

      def estimate_cost(usage)
        usd = (usage["prompt_tokens"].to_i / 1_000_000.0 * COST_INPUT_PER_M_USD) +
              (usage["completion_tokens"].to_i / 1_000_000.0 * COST_OUTPUT_PER_M_USD)
        # round(6) evita que 1.2 × 100 = 120.00000000000001 suba a 121.
        (usd * 100).round(6).ceil
      end
    end
  end
end
