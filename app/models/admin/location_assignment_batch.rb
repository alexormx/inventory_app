# frozen_string_literal: true

module Admin
  # Lo que el operador va juntando mientras trabaja parado frente a UN estante:
  # "aquí van 5 de este modelo, 3 de este otro, 2 de aquél".
  #
  # NO es el carrito del cliente. No toca Cart ni CartItem ni nada del checkout;
  # es una lista temporal de trabajo del almacén y vive en la sesión.
  #
  # Tampoco es la fuente de verdad: es una nota mental del operador. Al confirmar,
  # el servicio vuelve a leer y bloquear el inventario real, así que lo que aquí
  # se muestre puede quedar obsoleto sin causar daño.
  class LocationAssignmentBatch
    KEY = 'location_assignment_batch'
    # La sesión va en cookie (4 KB): un lote enorme no cabría. En la práctica un
    # estante no recibe decenas de SKU distintos de una sentada.
    MAX_LINES = 40

    class TooManyLines < StandardError; end

    def initialize(session)
      @session = session
      @session[KEY] ||= { 'location_id' => nil, 'lines' => {} }
      @session[KEY]['lines'] ||= {}
    end

    def location_id = data['location_id']

    def location
      return if location_id.blank?

      @location ||= InventoryLocation.find_by(id: location_id)
    end

    def location=(new_location_id)
      data['location_id'] = new_location_id.presence && new_location_id.to_i
      @location = nil
    end

    # product_id => quantity
    def lines = data['lines']

    delegate :empty?, to: :lines
    def product_count = lines.size
    def total_units = lines.values.sum(&:to_i)

    # Sumar en lugar de duplicar: agregar el mismo modelo dos veces es el
    # operador encontrando más piezas, no una línea nueva.
    def add(product_id, quantity)
      key = product_id.to_s
      raise TooManyLines if !lines.key?(key) && lines.size >= MAX_LINES

      lines[key] = lines.fetch(key, 0).to_i + quantity.to_i
    end

    def set_quantity(product_id, quantity)
      key = product_id.to_s
      quantity = quantity.to_i
      quantity.positive? ? lines[key] = quantity : lines.delete(key)
    end

    def remove(product_id) = lines.delete(product_id.to_s)

    def clear_lines
      data['lines'] = {}
    end

    def clear
      @session[KEY] = { 'location_id' => nil, 'lines' => {} }
      @location = nil
    end

    # Líneas listas para el servicio, con el producto cargado para mostrarlo.
    def detailed_lines
      return [] if empty?

      products = Product.where(id: lines.keys)
                        .includes(product_images_attachments: :blob)
                        .index_by { |p| p.id.to_s }
      lines.filter_map do |product_id, quantity|
        product = products[product_id]
        next unless product

        { product: product, quantity: quantity.to_i }
      end
    end

    def service_lines
      lines.map { |product_id, quantity| { product_id: product_id, quantity: quantity } }
    end

    private

    def data = @session[KEY]
  end
end
