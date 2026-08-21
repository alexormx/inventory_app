# frozen_string_literal: true

module Admin
  # Fachada del lote de ubicación sobre LocationAssignmentDraft.
  #
  # Antes esto guardaba el lote dentro de la sesión, y la sesión de esta app va
  # en cookie: por eso existía MAX_LINES = 40. El tope no era una regla del
  # almacén, era el tamaño de la cookie. Ahora el borrador vive en la base y el
  # único límite es el inventario que de verdad se puede ubicar.
  #
  # Se conserva esta clase para no reescribir controladores y vistas: la interfaz
  # es la misma, lo que cambió es dónde se guarda.
  class LocationAssignmentBatch
    ExceedsAvailable = LocationAssignmentDraft::ExceedsAvailable

    def self.for(user) = new(LocationAssignmentDraft.for(user))

    def initialize(draft)
      @draft = draft
    end

    attr_reader :draft

    delegate :location, :location=, :location_id, :empty?, :product_count, :total_units,
             :assignable_for, :pending_for, :pending_map, :remaining_addable,
             :add, :add_all, :set_quantity, :remove, :clear_lines,
             :detailed_lines, :service_lines, :consume!, :just_assigned?,
             to: :draft
  end
end
