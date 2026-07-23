# frozen_string_literal: true

module Products
  # Detecta resurtidos de inventario tras la recepción de una Purchase Order.
  #
  # La recepción mueve piezas in_transit -> available con `update_all`, saltando
  # callbacks. Este servicio recibe el conteo de piezas :available que cada
  # producto tenía ANTES de la recepción (`prev_available_counts`) y sella el
  # evento solo cuando hubo transición 0 -> positivo:
  #   - primera vez (first_stocked_at nil) => carga inicial, sin badge
  #   - veces posteriores => restocked_at (badge "Recién resurtido")
  # Los resurtidos parciales (había stock > 0) se ignoran porque el conteo previo
  # no era cero.
  class RestockDetector
    def self.call(product_ids, prev_available_counts:)
      new(product_ids, prev_available_counts).call
    end

    def initialize(product_ids, prev_available_counts)
      @product_ids = Array(product_ids).compact.uniq
      @prev_available_counts = prev_available_counts || {}
    end

    def call
      return if @product_ids.empty?

      current = Inventory.where(product_id: @product_ids, status: :available)
                         .group(:product_id).count

      Product.where(id: @product_ids).find_each do |product|
        was_zero = @prev_available_counts[product.id].to_i.zero?
        now_positive = current[product.id].to_i.positive?
        next unless was_zero && now_positive

        product.mark_restock_from_receipt!(was_zero: true)
      end
    end
  end
end
