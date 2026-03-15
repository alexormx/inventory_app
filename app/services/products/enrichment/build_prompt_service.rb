# frozen_string_literal: true

module Products
  module Enrichment
    # Builds the OpenAI prompt (system + user) from a product context hash.
    # Returns a Hash with :system and :user keys.
    class BuildPromptService
      PROMPT_VERSION = "v2"

      SYSTEM_PROMPT = <<~SYSTEM.freeze
        Eres un experto en productos coleccionables y autos a escala (diecast). Tu tarea es generar descripciones de producto y atributos técnicos para una tienda en línea mexicana llamada "Pasatiempos a Escala".

        REGLAS ESTRICTAS:
        1. Responde SÓLO en español de México.
        2. Genera una descripción de producto atractiva para SEO y compradores.
        3. La descripción DEBE venir en texto plano estructurado, no en un solo párrafo, usando EXACTAMENTE estas secciones y títulos:
           Resumen:
           Ficha del modelo:
           Puntos destacados:
           Historia y contexto:
           Cierre:
        4. En "Ficha del modelo" usa líneas cortas o viñetas con datos confirmados; si un dato no es confiable, omítelo.
        5. En "Puntos destacados" incluye 3 a 5 viñetas breves, claras y orientadas a venta/colección.
        6. La descripción completa debe mantenerse en un rango aproximado de 140 a 220 palabras.
        7. Genera TODOS los atributos solicitados basándote en el nombre del producto, marca, y datos disponibles.
        8. Si NO tienes certeza de un atributo, usa null y agrega un warning. NUNCA inventes datos.
        9. Para atributos booleanos (apertura, suspensión), responde "true" o "false".
        10. Para fechas, usa formato ISO 8601 (YYYY-MM-DD).
        11. Incluye un confidence_score de 0.0 a 1.0 que indique tu nivel de certeza general.
        12. Incluye warnings como array de strings señalando cualquier dato del que no estés seguro.
        13. Responde EXCLUSIVAMENTE con JSON válido, sin texto adicional.
      SYSTEM

      def initialize(context)
        @context = context
      end

      def call
        {
          system: SYSTEM_PROMPT,
          user: build_user_prompt,
          version: PROMPT_VERSION
        }
      end

      private

      def build_user_prompt
        parts = []
        parts << "Genera la descripción y atributos para el siguiente producto:\n"
        parts << "DATOS DEL PRODUCTO:"
        parts << "- Nombre: #{@context[:product_name]}"
        parts << "- SKU: #{@context[:product_sku]}"
        parts << "- Marca: #{@context[:brand]}"
        parts << "- Categoría: #{@context[:category]}"
        parts << "- Precio de venta: $#{@context[:selling_price]} MXN"
        parts << "- Código de barras: #{@context[:barcode]}" if @context[:barcode].present?
        parts << "- Código proveedor: #{@context[:supplier_code]}" if @context[:supplier_code].present?
        parts << "- Fecha lanzamiento: #{@context[:launch_date]}" if @context[:launch_date].present?

        if @context[:custom_attributes].present? && @context[:custom_attributes].any?
          parts << "\nATRIBUTOS ACTUALES (pueden tener errores o estar incompletos):"
          @context[:custom_attributes].each do |key, value|
            parts << "  - #{key}: #{value}"
          end
        end

        if @context[:dimensions].present?
          dims = @context[:dimensions]
          parts << "\nDIMENSIONES DEL EMPAQUE:"
          parts << "  - Peso: #{dims[:weight_gr]}g"
          parts << "  - Largo: #{dims[:length_cm]}cm x Ancho: #{dims[:width_cm]}cm x Alto: #{dims[:height_cm]}cm"
        end

        if @context[:description].present?
          parts << "\nDESCRIPCIÓN ACTUAL (mejorar sin perder información):"
          parts << @context[:description]
        end

        parts << <<~STRUCTURE

          FORMATO OBLIGATORIO DE LA DESCRIPCIÓN (`description_es`):
          Resumen:
          [1 párrafo breve de apertura]

          Ficha del modelo:
          - Marca o fabricante
          - Línea o colección
          - Modelo
          - Escala
          - Material

          Puntos destacados:
          - 3 a 5 viñetas con rasgos clave del producto

          Historia y contexto:
          [1 párrafo con contexto del modelo, versión, serie o relevancia]

          Cierre:
          [1 párrafo final orientado a coleccionistas o compra]

          IMPORTANTE:
          - `description_es` debe quedar en texto plano con saltos de línea.
          - No uses HTML.
          - No juntes todo en un solo párrafo.
          - Mantén la estructura anterior incluso si algunos datos son limitados.
        STRUCTURE

        parts << build_template_instructions
        parts << build_json_schema

        parts.compact.join("\n")
      end

      def build_template_instructions
        template = @context[:template]
        return nil unless template

        lines = ["\nATRIBUTOS REQUERIDOS POR LA CATEGORÍA '#{template[:category]}':", "Genera TODOS los siguientes atributos:"]

        template[:schema].each do |attr|
          req = attr["required"] ? " (OBLIGATORIO)" : " (opcional)"
          example = attr["example"].present? ? " — ejemplo: #{attr["example"]}" : ""
          lines << "  - #{attr["key"]} [#{attr["type"]}]#{req}#{example}"
        end

        lines.join("\n")
      end

      def build_json_schema
        <<~SCHEMA

          RESPONDE EXACTAMENTE con este esquema JSON:
          {
            "product_name": "string — nombre optimizado para SEO",
            "description_es": "string — descripción estructurada en texto plano con las secciones Resumen, Ficha del modelo, Puntos destacados, Historia y contexto, Cierre",
            "highlights": ["string — 3-5 puntos destacados del producto"],
            "attributes": {
              "key": "value para cada atributo de la categoría"
            },
            "seo_keywords": ["string — 5-8 palabras clave relevantes en español"],
            "warnings": ["string — advertencias si algún dato es incierto"],
            "confidence_score": 0.85
          }
        SCHEMA
      end
    end
  end
end
