# frozen_string_literal: true

module Products
  module Enrichment
    # Builds the OpenAI prompt (system + user) from a product context hash.
    # Returns a Hash with :system and :user keys.
    class BuildPromptService
      PROMPT_VERSION = "v3"

      SYSTEM_PROMPT = <<~SYSTEM.freeze
        Eres un experto en productos coleccionables y autos a escala (diecast). Tu tarea es generar descripciones de producto y atributos técnicos para una tienda en línea mexicana llamada "Pasatiempos a Escala".

        REGLAS ESTRICTAS:
        1. Responde SÓLO en español de México.
        2. Genera una descripción de producto atractiva para SEO y compradores.
        3. La descripción DEBE venir en texto plano natural, dividida en 2 o 3 párrafos breves y fluidos, nunca en un solo bloque.
        4. NO uses títulos o encabezados literales como "Resumen:", "Ficha del modelo:", "Puntos destacados:", "Historia y contexto:" o "Cierre:".
        5. NO uses listas, viñetas ni etiquetas visibles dentro de `description_es`.
        6. El tono debe ser entusiasta, descriptivo, confiable y ligeramente persuasivo, pensado para coleccionistas y compradores.
        7. Menciona sólo datos confirmados dentro de la descripción. Si un dato técnico no es confiable o no está disponible, omítelo del texto narrativo.
        8. Genera TODOS los atributos solicitados basándote en el nombre del producto, marca, y datos disponibles.
        9. Si NO tienes certeza de un atributo, usa null ÚNICAMENTE dentro de `attributes` y agrega un warning. NUNCA inventes datos.
        10. La palabra "null" JAMÁS debe aparecer en `description_es`, `highlights`, `product_name` o `seo_keywords`.
        11. Para atributos booleanos (apertura, suspensión), responde "true" o "false".
        12. Para fechas, usa formato ISO 8601 (YYYY-MM-DD).
        13. Incluye un confidence_score de 0.0 a 1.0 que indique tu nivel de certeza general.
        14. Incluye warnings como array de strings señalando cualquier dato del que no estés seguro.
        15. Responde EXCLUSIVAMENTE con JSON válido, sin texto adicional.
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

          ESTILO OBLIGATORIO DE LA DESCRIPCIÓN (`description_es`):
          - Escribe 2 o 3 párrafos breves en texto plano con saltos de línea entre párrafos.
          - Abre con una presentación atractiva del producto y su valor para un coleccionista o comprador.
          - Integra de forma natural los detalles confirmados del modelo, la marca, la colección, el color o la propuesta de valor, sin sonar robótico.
          - Cierra con una idea de deseo de compra o valor de exhibición, pero sin exageraciones vacías.

          IMPORTANTE:
          - No uses HTML.
          - No uses encabezados visibles ni títulos literales.
          - No uses viñetas dentro de `description_es`.
          - No escribas la palabra "null" dentro de `description_es`.
          - Si faltan datos técnicos, omítelos del relato y repórtalos en `warnings` o como null dentro de `attributes`.
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
            "description_es": "string — descripción natural en español, en 2 o 3 párrafos, sin encabezados visibles, sin viñetas y sin la palabra null",
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
