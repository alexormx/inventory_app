# frozen_string_literal: true

# Lo que el operador va juntando mientras trabaja parado frente a UN estante:
# "aquí van 5 de este modelo, 3 de este otro, 2 de aquél".
#
# NO es el carrito del cliente: no toca Cart ni CartItem ni el checkout. Tampoco
# reserva inventario — meter algo aquí no aparta ninguna pieza. La verdad sigue
# siendo la tabla inventories, y al confirmar el servicio vuelve a leer y a
# bloquear las filas reales.
#
# Vive en la base y no en la sesión porque la sesión de esta app va en cookie: un
# lote grande no cabía, y de ahí venía el viejo tope de 40 líneas.
class LocationAssignmentDraft < ApplicationRecord
  LIFETIME = 7.days

  belongs_to :user
  belongs_to :inventory_location, optional: true
  has_many :lines, class_name: 'LocationAssignmentDraftLine', dependent: :delete_all,
                   inverse_of: :location_assignment_draft

  # Pedir más de lo que queda por ubicar no se recorta en silencio: el operador
  # tecleó un número y merece saber por qué no se aceptó.
  class ExceedsAvailable < StandardError
    attr_reader :product, :requested, :remaining

    def initialize(product:, requested:, remaining:)
      @product = product
      @requested = requested
      @remaining = remaining
      super(build_message)
    end

    private

    def build_message
      if remaining.zero?
        "#{product.product_name}: ya tienes en el lote todo el inventario que se puede ubicar."
      else
        "#{product.product_name}: solicitaste #{requested} y sólo puedes agregar #{remaining} más."
      end
    end
  end

  # El índice único por usuario es quien resuelve dos primeras peticiones
  # simultáneas. find_or_create_by! puede hacer dos INSERT y dejar escapar
  # RecordNotUnique; create_or_find_by! usa precisamente ese índice para volver
  # a leer la fila ganadora.
  def self.for(user)
    draft = create_or_find_by!(user: user) { |record| record.expires_at = LIFETIME.from_now }
    draft.reset_if_expired!
  end

  def location = inventory_location

  # Cambiar de estante y, cuando corresponde, descartar las líneas tiene que ser
  # una sola sección crítica. Dos pestañas no pueden agregar una línea entre el
  # vaciado y el cambio de ubicación.
  def change_location(new_location_id, discard_lines: false)
    requested_id = new_location_id.presence && new_location_id.to_i

    with_lock do
      changing = inventory_location_id != requested_id
      return false if changing && lines.exists? && !discard_lines

      lines.delete_all if changing && discard_lines
      self.inventory_location_id = requested_id
      refresh_activity!(clear_assignment_marker: true)
      true
    end
  end

  def location_id = inventory_location_id

  delegate :empty?, to: :lines
  def product_count = lines.size
  def total_units = lines.sum(:quantity)

  # Cuántas piezas de este producto pueden ubicarse HOY, sin contar el lote.
  def assignable_for(product_id)
    Inventories::LocationAssignment.eligible_scope(product_id).count
  end

  # Todas las cantidades pendientes de una vez: las filas de resultados necesitan
  # "En lote" por producto y preguntarlo una por una sería un N+1.
  def pending_map = lines.pluck(:product_id, :quantity).to_h

  def pending_for(product_id)
    lines.where(product_id: product_id).pick(:quantity).to_i
  end

  def remaining_addable(product_id)
    [assignable_for(product_id) - pending_for(product_id), 0].max
  end

  # Agrega sumando sobre la línea existente, nunca duplicándola.
  #
  # La comprobación va DENTRO de una transacción con la fila del borrador
  # bloqueada: sin eso, dos clics seguidos leen ambos el mismo "quedan 2" y
  # acaban metiendo 4. El límite real es el inventario, no el formulario.
  def add(product_id, quantity)
    quantity = Integer(quantity.to_s.strip, 10)
    raise ArgumentError unless quantity.positive?

    with_lock do
      remaining = remaining_addable(product_id)
      if quantity > remaining
        raise ExceedsAvailable.new(product: Product.find(product_id), requested: quantity,
                                   remaining: remaining)
      end

      result = upsert_line(product_id, pending_for(product_id) + quantity)
      refresh_activity!(clear_assignment_marker: true)
      result
    end
  end

  # "Agregar todas las disponibles": la cantidad la calcula el servidor al
  # momento, no el navegador. Pulsarlo dos veces deja el lote igual.
  def add_all(product_id)
    with_lock do
      remaining = remaining_addable(product_id)
      return 0 if remaining.zero?

      upsert_line(product_id, pending_for(product_id) + remaining)
      refresh_activity!(clear_assignment_marker: true)
      remaining
    end
  end

  def set_quantity(product_id, quantity)
    quantity = quantity.to_i
    with_lock do
      if quantity.positive?
        # Editar a mano tampoco puede pasarse del inventario real.
        capped = [quantity, assignable_for(product_id)].min
        capped.positive? ? upsert_line(product_id, capped) : lines.where(product_id: product_id).delete_all
      else
        lines.where(product_id: product_id).delete_all
      end
      refresh_activity!(clear_assignment_marker: true)
    end
  end

  def remove(product_id)
    with_lock do
      removed = lines.where(product_id: product_id).delete_all
      refresh_activity!(clear_assignment_marker: true)
      removed
    end
  end

  def clear_lines
    with_lock do
      removed = lines.delete_all
      refresh_activity!(clear_assignment_marker: true)
      removed
    end
  end

  # Líneas listas para el servicio, con el producto cargado para mostrarlo.
  def detailed_lines
    ordered_lines.map { |line| { product: line.product, quantity: line.quantity } }
  end

  def service_lines
    lines.pluck(:product_id, :quantity).map { |product_id, quantity| { product_id: product_id, quantity: quantity } }
  end

  # Consume el borrador manteniendo su fila bloqueada durante el trabajo que
  # recibe el bloque. Las líneas se borran SÓLO después de que ese trabajo
  # termina: si el servicio de inventario falla, el lote nunca desaparece, ni
  # siquiera bajo contención entre dos administradores.
  #
  # Un segundo envío del mismo lote espera el lock y después encuentra el
  # borrador vacío, que es lo que hace inofensivo el doble clic final.
  def consume!
    with_lock do
      taken = service_lines
      return taken if taken.empty?

      yield(taken) if block_given?
      lines.delete_all
      update!(last_assigned_at: Time.current, expires_at: LIFETIME.from_now)
      taken
    end
  end

  # Vacío justo después de asignar, o vacío porque nunca se agregó nada. Al
  # operador que hizo doble clic hay que decirle lo primero.
  def just_assigned? = last_assigned_at.present? && last_assigned_at > 30.seconds.ago

  # No borra la fila (hay como máximo una por administrador); sólo descarta el
  # contexto abandonado. Es limpieza acotada y oportunista, sin depender de un
  # proceso local, cron o worker.
  def reset_if_expired!
    with_lock do
      if expires_at <= Time.current
        lines.delete_all
        update!(inventory_location: nil, last_assigned_at: nil, expires_at: LIFETIME.from_now)
      end
    end
    self
  end

  private

  def ordered_lines
    lines.includes(product: { product_images_attachments: :blob })
         .joins(:product).order('products.product_name ASC')
  end

  def upsert_line(product_id, quantity)
    line = lines.find_or_initialize_by(product_id: product_id)
    line.quantity = quantity
    line.save!
    quantity
  end

  def refresh_activity!(clear_assignment_marker: false)
    self.last_assigned_at = nil if clear_assignment_marker
    self.expires_at = LIFETIME.from_now
    save!
  end
end
