# frozen_string_literal: true

module Products
  module Enrichment
    # Esquema estricto (Structured Outputs) de la respuesta. Con plantilla, los
    # atributos son sus llaves (texto o null, todas presentes, ninguna extra).
    # Sin plantilla son una lista de pares clave–valor que la IA propone: un
    # objeto vacío en modo estricto hacía que el modelo escribiera tabuladores
    # sin fin hasta el límite de tokens (producción, 2026-10-06).
    module ResponseSchema
      NULLABLE_STRING = { type: %w[string null] }.freeze
      STRING_LIST = { type: 'array', items: { type: 'string' } }.freeze
      ATTRIBUTE_PAIRS = {
        type: 'array',
        items: { type: 'object', additionalProperties: false, required: %w[key value],
                 properties: { key: { type: 'string' }, value: NULLABLE_STRING } }
      }.freeze

      module_function

      def for(template)
        keys = template ? template.attribute_keys : []
        {
          type: 'object', additionalProperties: false,
          required: %w[product_name description_es highlights attributes seo_keywords warnings confidence_score],
          properties: {
            product_name: { type: 'string' },
            description_es: { type: 'string' },
            highlights: STRING_LIST,
            attributes: attributes_for(keys),
            seo_keywords: STRING_LIST,
            warnings: STRING_LIST,
            confidence_score: { type: 'number' }
          }
        }
      end

      def attributes_for(keys)
        return ATTRIBUTE_PAIRS if keys.empty?

        { type: 'object', additionalProperties: false, required: keys, properties: keys.index_with { NULLABLE_STRING } }
      end
    end
  end
end
