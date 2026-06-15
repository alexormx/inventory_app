# frozen_string_literal: true

module Products
  module Enrichment
    # Builds the OpenAI prompt (system + user) from a product context hash.
    # Returns a Hash with :system and :user keys.
    class BuildPromptService
      PROMPT_VERSION = "v6"

      SYSTEM_PROMPT = <<~SYSTEM.freeze
        Eres un experto en productos coleccionables y autos a escala (diecast). Tu tarea es generar descripciones de producto y atributos técnicos para una tienda en línea mexicana llamada "Pasatiempos a Escala".

        REGLAS ESTRICTAS:
        1. Responde SÓLO en español de México.
        2. Genera una descripción de producto clara, factual y útil para el comprador, optimizada para SEO de forma natural (sin saturar de palabras clave).
        3. La descripción DEBE venir en texto plano natural, en 1 o 2 párrafos breves como máximo, nunca en un solo bloque largo.
        4. NO uses títulos o encabezados literales como "Resumen:", "Ficha del modelo:", "Puntos destacados:", "Historia y contexto:" o "Cierre:".
        5. NO uses listas, viñetas ni etiquetas visibles dentro de `description_es`.
        6. El tono debe ser simple, profesional y factual. Describe el producto con claridad y evita el lenguaje publicitario vacío.
        7. PROHIBIDO usar frases exageradas o de relleno como "impresionante", "joya", "magnífico", "espectacular", "pieza de conversación", "no dejes pasar" o "imperdible". Prefiere detalles concretos sobre marketing genérico.
        8. Usa ÚNICAMENTE datos disponibles del producto (nombre, marca, línea o colección, escala, color, material, código de barras, SKU, categoría y atributos personalizados). NUNCA inventes datos.
        9. Menciona la relevancia para coleccionistas sólo cuando sea razonable y se base en los datos del producto (marca, modelo de auto real, serie). No la fuerces.
        10. Menciona sólo datos confirmados dentro de la descripción. Si un dato no es confiable o no está disponible, omítelo del texto.
        11. Genera TODOS los atributos solicitados basándote en el nombre del producto, marca, y datos disponibles.
        12. Si NO tienes certeza de un atributo, usa null ÚNICAMENTE dentro de `attributes` y agrega un warning. NUNCA inventes datos.
        13. La palabra "null" JAMÁS debe aparecer en `description_es`, `highlights`, `product_name` o `seo_keywords`.
        14. Para atributos booleanos (apertura, suspensión), responde "true" o "false".
        15. Para fechas, usa formato ISO 8601 (YYYY-MM-DD).
        16. Incluye un confidence_score de 0.0 a 1.0 que indique tu nivel de certeza general.
        17. Incluye warnings como array de strings señalando cualquier dato del que no estés seguro.
        18. Responde EXCLUSIVAMENTE con JSON válido, sin texto adicional.
        19. NO menciones en `description_es` dimensiones o medidas del empaque (largo, ancho, alto en cm/mm/pulgadas) ni peso (g/kg); esos datos viven sólo en `attributes`. La escala, el color y el material SÍ pueden mencionarse cuando estén disponibles.
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

        parts << build_supplier_catalog_section

        parts << <<~STRUCTURE

          ESTILO OBLIGATORIO DE LA DESCRIPCIÓN (`description_es`):
          - Escribe 1 o 2 párrafos breves en texto plano (máximo dos), con un salto de línea entre párrafos si usas dos.
          - Comienza identificando el producto con datos concretos: nombre del modelo, marca y, si están disponibles, línea o colección, escala, color y material.
          - Mantén un tono simple, profesional y factual. Prefiere detalles concretos sobre frases de marketing genéricas.
          - Menciona la relevancia para coleccionistas sólo si es razonable según los datos (marca, modelo de auto real, serie).

          IMPORTANTE:
          - No uses HTML.
          - No uses encabezados visibles ni títulos literales.
          - No uses viñetas dentro de `description_es`.
          - No escribas la palabra "null" dentro de `description_es`.
          - PROHIBIDO usar frases exageradas o de relleno: "impresionante", "joya", "magnífico", "espectacular", "pieza de conversación", "no dejes pasar", "imperdible" y similares.
          - No menciones dimensiones del empaque (cm, mm, pulgadas, largo/ancho/alto) ni peso (g/kg); eso vive sólo en `attributes`. La escala, el color y el material sí pueden mencionarse.
          - No inventes datos: usa únicamente la información proporcionada del producto. Si faltan datos, omítelos del relato y repórtalos en `warnings` o como null dentro de `attributes`.
        STRUCTURE

        parts << build_template_instructions
        parts << build_json_schema

        parts.compact.join("\n")
      end

      def build_supplier_catalog_section
        ctx = @context[:supplier_context]
        return nil unless ctx

        item = ctx[:catalog_item]
        return nil unless item

        lines = ["\nDATOS DEL CATÁLOGO DEL PROVEEDOR (fuente confiable, usar para enriquecer):"]
        lines << "- Nombre canónico: #{item[:canonical_name]}" if item[:canonical_name].present?
        lines << "- Marca proveedor: #{item[:canonical_brand]}" if item[:canonical_brand].present?
        lines << "- Serie/Colección: #{item[:canonical_series]}" if item[:canonical_series].present?
        lines << "- Tipo de artículo: #{item[:canonical_item_type]}" if item[:canonical_item_type].present?
        lines << "- Fecha de lanzamiento: #{item[:canonical_release_date]}" if item[:canonical_release_date].present?
        lines << "- Precio proveedor: #{item[:canonical_price]} #{item[:currency]}" if item[:canonical_price].present?
        lines << "- Estado: #{item[:canonical_status]}" if item[:canonical_status].present?
        lines << "- Código de barras: #{item[:barcode]}" if item[:barcode].present?
        lines << "- URL fuente: #{item[:source_url]}" if item[:source_url].present?

        if item[:description_raw].present?
          lines << "\nDESCRIPCIÓN DEL PROVEEDOR (referencia, adaptar al estilo de la tienda):"
          lines << item[:description_raw].truncate(2000)
        end

        if item[:details_payload].present? && item[:details_payload].is_a?(Hash) && item[:details_payload].any?
          lines << "\nDETALLES TÉCNICOS DEL PROVEEDOR:"
          item[:details_payload].each do |key, value|
            lines << "  - #{key}: #{value}" if value.present?
          end
        end

        sources = ctx[:sources]
        if sources.present? && sources.any?
          sources.each do |src|
            next unless src[:normalized_payload].present? && src[:normalized_payload].is_a?(Hash)
            lines << "\nFUENTE ADICIONAL (#{src[:source]}):"
            src[:normalized_payload].each do |key, value|
              lines << "  - #{key}: #{value}" if value.present?
            end
          end
        end

        lines.join("\n")
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
            "description_es": "string — descripción natural en español, clara y factual, en 1 o 2 párrafos, sin encabezados visibles, sin viñetas, sin frases exageradas y sin la palabra null",
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
