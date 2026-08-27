# frozen_string_literal: true

module Inventories
  # Ubica VARIOS productos en UNA sola ubicación, en una sola operación.
  #
  # Es el gesto físico real del almacén: el operador se planta en un estante y
  # coloca ahí lo que trae —5 de un modelo, 3 de otro, 2 de otro— y luego dice
  # "listo". Por eso el lote es todo o nada: si al confirmar resulta que de uno
  # de los modelos ya sólo quedan 2 y pedía 3, no se guarda NADA. Dejar dos
  # líneas aplicadas y una fallida rompería la idea de "ya acomodé esta caja".
  #
  # No reimplementa nada: la elegibilidad, el FIFO, el bloqueo, la validación de
  # ubicación y la auditoría son los mismos de Inventories::LocationAssignment
  # que usa la asignación de una sola línea.
  class BulkAssignLocationBatchService
    class Error < StandardError; end
    class EmptyBatch < Error; end
    class InvalidQuantity < Error; end
    class UnauthorizedActor < Error; end
    class ProductNotFound < Error; end

    InvalidLocation = Inventories::LocationAssignment::InvalidLocation

    SOURCE = 'bulk_product_quantity_batch'

    # Detalle por línea de lo que faltó, para poder decirle al operador
    # exactamente qué producto lo bloqueó y con qué números.
    Shortage = Struct.new(:product, :requested, :available, keyword_init: true)

    class InsufficientEligibleInventory < Error
      attr_reader :shortages

      def initialize(shortages)
        @shortages = shortages
        detail = shortages.map do |s|
          "#{s.product.product_name}: solicitadas #{s.requested}, disponibles #{s.available}"
        end.join('; ')
        super("No se realizó ninguna asignación. #{detail}.")
      end
    end

    Result = Struct.new(:location, :lines, :batch_id, keyword_init: true) do
      def assigned_count = lines.sum { |line| line[:inventories].size }
      def product_count  = lines.size
    end

    def self.call(...) = new(...).call

    # lines: [{ product_id:, quantity: }, ...]
    def initialize(lines:, location_id:, actor:, notes: nil)
      @lines = Array(lines)
      @location_id = location_id
      @actor = actor
      @notes = notes.to_s.strip.presence
    end

    def call
      raise EmptyBatch, 'Agrega al menos un producto antes de confirmar.' if @lines.empty?

      validate_actor!
      requested = normalized_lines!
      batch_id = SecureRandom.uuid

      Inventory.transaction do
        locked_products = Product.where(id: requested.map { |line| line[:product].id })
                                 .lock
                                 .order(:id)
                                 .index_by(&:id)
        raise ProductNotFound, 'Uno de los productos ya no existe.' if locked_products.size != requested.size

        requested = requested.map do |line|
          line.merge(product: locked_products.fetch(line[:product].id))
        end
        location = Inventories::LocationAssignment.validated_leaf_location!(@location_id)

        # PASO 1 — bloquear y verificar TODAS las líneas antes de escribir una
        # sola. Se recorren en orden de product_id para que dos operadores
        # concurrentes tomen los bloqueos siempre en la misma secuencia y no se
        # queden trabados uno contra el otro.
        prepared = requested.sort_by { |line| line[:product].id }.map do |line|
          rows = Inventories::LocationAssignment.lock_fifo_rows!(line[:product].id, line[:quantity])
          line.merge(inventories: rows)
        end

        shortages = prepared.filter_map do |line|
          next if line[:inventories].size >= line[:quantity]

          Shortage.new(product: line[:product], requested: line[:quantity],
                       available: line[:inventories].size)
        end
        raise InsufficientEligibleInventory, shortages if shortages.any?

        # PASO 2 — recién ahora se escribe. Las filas siguen bloqueadas desde el
        # paso 1, así que nadie pudo llevárselas en medio.
        prepared.each do |line|
          line[:inventories].each do |inventory|
            inventory.defer_preorder_reconciliation = true
            Inventories::LocationAssignment.assign_located!(
              inventory, location,
              actor: @actor, source: SOURCE, notes: @notes, batch_id: batch_id
            )
          end
        end

        # No se puede fusionar con el bucle anterior: la reconciliación tiene que
        # ver el lote COMPLETO ya ubicado. Si se asignara línea por línea, una
        # preventa vieja podría quedarse sin piezas que aún no se habían ubicado.
        # rubocop:disable Style/CombinableLoops
        prepared.each { |line| Preorders::PreorderAllocator.new(line[:product]).call }
        # rubocop:enable Style/CombinableLoops

        Result.new(location: location, lines: prepared, batch_id: batch_id)
      end
    end

    private

    def validate_actor!
      return if @actor.is_a?(User) && @actor.persisted? && !@actor.destroyed? && @actor.admin?

      raise UnauthorizedActor, 'Ubicar inventario requiere una sesión de administrador.'
    end

    # Normaliza y combina: si el mismo producto llega dos veces, se suman las
    # cantidades en lugar de pelearse por las mismas piezas.
    def normalized_lines!
      combined = Hash.new(0)
      @lines.each do |line|
        product_id = Integer(line[:product_id].to_s.strip, 10)
        quantity = Integer(line[:quantity].to_s.strip, 10)
        raise InvalidQuantity, 'La cantidad debe ser mayor a cero.' unless quantity.positive?

        combined[product_id] += quantity
      rescue ArgumentError, TypeError
        raise InvalidQuantity, 'La cantidad debe ser un número entero.'
      end

      products = Product.where(id: combined.keys).index_by(&:id)
      combined.map do |product_id, quantity|
        product = products[product_id]
        raise ProductNotFound, 'Uno de los productos ya no existe.' unless product

        { product: product, quantity: quantity }
      end
    end
  end
end
