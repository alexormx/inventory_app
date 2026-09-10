# frozen_string_literal: true

module Inventories
  # Asigna una ubicación física a N piezas de un producto.
  #
  # El almacén no etiqueta cada pieza: dos unidades del mismo SKU son
  # intercambiables y nadie puede decir "ésta es la Inventory 12345". Lo que el
  # administrador sí sabe es "encontré 10 piezas de este producto y las puse en
  # este estante". Por eso la entrada es producto + cantidad + ubicación, y es
  # el sistema quien elige las filas concretas.
  #
  # Inventory.id sigue siendo la identidad contable: se elige por FIFO, se
  # bloquea y se audita fila por fila. Simplemente no se le pide al usuario.
  #
  # Concurrencia: aquí no sirve el expected_snapshot de la verificación
  # individual, porque el administrador nunca vio unidades concretas que
  # comparar. Se usa bloqueo pesimista (SELECT FOR UPDATE) sobre las filas
  # elegidas, que además es más fuerte: dos administradores no pueden llevarse
  # la misma pieza.
  class BulkAssignLocationService
    class Error < StandardError; end
    class InvalidQuantity < Error; end
    class UnauthorizedActor < Error; end
    class ProductNotFound < Error; end

    # Se pidieron más piezas de las que quedan sin ubicar. No se asigna nada:
    # "puse 10 en el estante" es verdad o no lo es.
    class InsufficientEligibleInventory < Error
      attr_reader :requested, :available

      def initialize(requested, available)
        @requested = requested
        @available = available
        super("Se solicitaron #{requested} unidades y sólo hay #{available} sin ubicación.")
      end
    end

    InvalidLocation = Inventories::LocationAssignment::InvalidLocation

    SOURCE = 'bulk_product_quantity'

    Result = Struct.new(:product, :location, :inventories, :events, keyword_init: true) do
      def assigned_count = inventories.size
    end

    def self.call(...) = new(...).call

    def initialize(product_id:, quantity:, location_id:, actor:, notes: nil)
      @product_id = product_id
      @quantity = quantity
      @location_id = location_id
      @actor = actor
      @notes = notes.to_s.strip.presence
    end

    def call
      quantity = validated_quantity!
      validate_actor!

      Inventory.transaction do
        product = Product.lock.find_by(id: @product_id)
        raise ProductNotFound, 'El producto no existe.' unless product

        location = Inventories::LocationAssignment.validated_leaf_location!(@location_id)

        # Se relee y se bloquea DENTRO de la transacción: el conteo que vio la
        # pantalla al cargar ya puede estar obsoleto.
        inventories = Inventories::LocationAssignment.lock_fifo_rows!(product.id, quantity)

        raise InsufficientEligibleInventory.new(quantity, inventories.size) if inventories.size < quantity

        events = inventories.map do |inventory|
          inventory.defer_preorder_reconciliation = true
          Inventories::LocationAssignment.assign_located!(
            inventory, location, actor: @actor, source: SOURCE, notes: @notes
          )
        end

        Preorders::PreorderAllocator.new(product).call

        Result.new(product: product, location: location, inventories: inventories, events: events)
      end
    end

    private

    def validated_quantity!
      quantity = Integer(@quantity.to_s.strip, 10)
      raise InvalidQuantity, 'La cantidad debe ser mayor a cero.' unless quantity.positive?

      quantity
    rescue ArgumentError, TypeError
      raise InvalidQuantity, 'La cantidad debe ser un número entero.'
    end

    def validate_actor!
      return if @actor.is_a?(User) && @actor.persisted? && !@actor.destroyed? && @actor.admin?

      raise UnauthorizedActor, 'Ubicar inventario requiere una sesión de administrador.'
    end
  end
end
