module CatalogPdf
  # Orquesta la construcción de los ítems del catálogo para la página de
  # generación (admin, solo local). Elige la fuente de datos (API de producción
  # o BD local), lista las categorías disponibles, filtra por las categorías
  # seleccionadas y ordena por: 1) el orden de categorías elegido por el usuario
  # y 2) un campo secundario (nombre, precio o código), asc o desc.
  class Builder
    SECONDARY_FIELDS = %w[name price code].freeze

    def initialize(source:, categories: [], sort: 'name', direction: 'asc',
                   api_url: nil, api_token: nil)
      @source = source == 'local' ? 'local' : 'api'
      @selected = Array(categories).reject(&:blank?)
      @sort = SECONDARY_FIELDS.include?(sort) ? sort : 'name'
      @direction = direction == 'desc' ? 'desc' : 'asc'
      @api_url = api_url
      @api_token = api_token
    end

    # Lista de categorías presentes en la fuente (sin descargar imágenes).
    def available_categories
      metadata.map { |item| item[:category] }.compact.uniq.sort
    end

    # Ítems finales, filtrados + ordenados, con la imagen ya embebida.
    # Si se pasa un bloque, se invoca con (current, total, name) justo antes
    # de embeber la imagen de cada producto (el paso lento), para reportar
    # progreso a la UI.
    def items
      list = selection
      total = list.size
      list.each_with_index.map do |item, i|
        yield(i + 1, total, item[:name]) if block_given?
        with_image(item)
      end
    end

    private

    # Ítems elegidos + ordenados, todavía sin imagen embebida.
    def selection
      @selection ||= begin
        order = (@selected.presence || available_categories)
        index = order.each_with_index.to_h

        chosen = metadata.select { |item| index.key?(item[:category]) }
        chosen.sort! { |a, b| compare(a, b, index) }
        chosen
      end
    end

    # Metadata (sin imagen embebida) cacheada para no pegarle dos veces a la
    # fuente entre listar categorías y construir los ítems.
    def metadata
      @metadata ||= @source == 'local' ? local_metadata : remote_metadata
    end

    def local_metadata
      ProductSource.ordered(Product.with_confirmed_location)
                   .map { |product| ProductSource.base_fields(product).merge(product: product) }
    end

    def remote_metadata
      RemoteSource.metadata(base_url: @api_url, token: @api_token)
    end

    def with_image(item)
      if @source == 'local'
        item.except(:product).merge(image: ProductSource.image_data_uri(item[:product]))
      else
        RemoteSource.embed_item(item)
      end
    end

    def compare(a, b, index)
      by_category = index[a[:category]] <=> index[b[:category]]
      return by_category unless by_category.zero?

      secondary = secondary_key(a) <=> secondary_key(b)
      @direction == 'desc' ? -secondary : secondary
    end

    def secondary_key(item)
      case @sort
      when 'price' then item[:price].to_f
      when 'code'  then item[:code].to_s
      else item[:name].to_s.downcase
      end
    end
  end
end
