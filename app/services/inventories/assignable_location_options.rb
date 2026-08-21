# frozen_string_literal: true

module Inventories
  # Opciones del selector de ubicación destino, con lo que YA hay guardado en
  # cada una.
  #
  # El operador elige el estante antes de ver su contenido, así que sin el conteo
  # tenía que seleccionar a ciegas para enterarse de si el estante estaba vacío o
  # ya casi lleno. La cifra es la misma que luego enseña "Actualmente en esta
  # ubicación" (mismo scope requiring_location), porque dos números distintos
  # para lo mismo en la misma pantalla se leen como un error.
  #
  # Sólo cuenta inventario COMPROMETIDO: el lote temporal de la sesión no entra
  # aquí, igual que no entra en el resumen.
  class AssignableLocationOptions
    def self.call(...) = new(...).call

    def call
      # Dos consultas fijas: el conteo agrupado y las hojas activas. Preguntar
      # por ubicación sería un N+1 sobre una lista que crece con la bodega.
      InventoryLocation.active.where.not(id: parent_ids).order(:path_cache, :name).map do |location|
        [label_for(location), location.id]
      end
    end

    private

    def counts
      @counts ||= Inventory.where.not(inventory_location_id: nil)
                           .requiring_location
                           .group(:inventory_location_id)
                           .count
    end

    # Padre de alguien = no es hoja. Recorrer llamando a leaf? hace una consulta
    # por ubicación.
    def parent_ids
      InventoryLocation.where.not(parent_id: nil).select(:parent_id)
    end

    def label_for(location)
      units = counts[location.id].to_i
      name = location.path_cache.presence || location.name
      "#{name} (#{location.code}) (#{units} #{units == 1 ? 'pieza' : 'piezas'})"
    end
  end
end
