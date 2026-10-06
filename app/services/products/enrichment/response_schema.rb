# frozen_string_literal: true

module Products
  module Enrichment
    # Esquema estricto (Structured Outputs) de la respuesta. Los atributos son
    # las llaves de la plantilla de la categoría (texto o null, todas presentes,
    # ninguna extra); sin plantilla, `attributes` es un objeto vacío.
    module ResponseSchema
      NULLABLE_STRING = { type: %w[string null] }.freeze
      STRING_LIST = { type: 'array', items: { type: 'string' } }.freeze

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
            attributes: { type: 'object', additionalProperties: false, required: keys,
                          properties: keys.index_with { NULLABLE_STRING } },
            seo_keywords: STRING_LIST,
            warnings: STRING_LIST,
            confidence_score: { type: 'number' }
          }
        }
      end
    end
  end
end
