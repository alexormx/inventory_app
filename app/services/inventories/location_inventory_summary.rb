# frozen_string_literal: true

module Inventories
  # Lo que YA está registrado en un estante, agrupado por producto.
  #
  # No tiene nada que ver con el lote temporal de la sesión: aquí sólo entran
  # filas de Inventory ya guardadas, con su inventory_location_id puesto. Meter
  # el lote aquí haría creer al operador que algo se movió antes de confirmar,
  # que es justo el error que esta pantalla tiene que evitar.
  class LocationInventorySummary
    Line = Struct.new(:product, :total, :available, :reserved, :in_transit, keyword_init: true)

    def self.for(location) = new(location)

    def initialize(location)
      @location = location
    end

    attr_reader :location

    delegate :present?, to: :location

    def lines
      @lines ||= build_lines
    end

    def total_units = @total_units ||= counts.values.sum

    def product_count = @product_count ||= counts.keys.map(&:first).uniq.size

    def available_units = units_with_status('available')
    def reserved_units = units_with_status('reserved')
    def in_transit_units = units_with_status('pre_reserved')

    private

    # Un solo group/count para todo el estante: totales, desglose por estatus y
    # las filas salen de aquí sin volver a la base por producto.
    def counts
      @counts ||= if location.blank?
                    {}
                  else
                    Inventory.where(inventory_location_id: location.id)
                             .requiring_location
                             .group(:product_id, :status)
                             .count
                  end
    end

    def units_with_status(status)
      counts.sum { |(_pid, row_status), n| row_status.to_s == status ? n : 0 }
    end

    def build_lines
      return [] if counts.empty?

      products = Product.where(id: counts.keys.map(&:first).uniq)
                        .includes(product_images_attachments: :blob)
                        .index_by(&:id)

      counts.group_by { |(product_id, _status), _n| product_id }
            .filter_map { |product_id, entries| line_for(products[product_id], entries) }
            .sort_by { |line| line.product.product_name.to_s.downcase }
    end

    def line_for(product, entries)
      return unless product

      by_status = entries.to_h { |(_pid, status), n| [status.to_s, n] }
      Line.new(
        product: product,
        total: by_status.values.sum,
        available: by_status['available'].to_i,
        reserved: by_status['reserved'].to_i,
        in_transit: by_status['pre_reserved'].to_i
      )
    end
  end
end
