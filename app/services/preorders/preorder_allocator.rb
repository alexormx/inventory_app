module Preorders
  class PreorderAllocator
    # Asigna nuevo stock disponible a preorders pendientes en orden FIFO
    def initialize(product, newly_available_units:)
      @product = product
      @remaining = newly_available_units.to_i
    end

    def call
      return if @remaining <= 0
      PreorderReservation.fifo_pending.where(product: @product).find_each do |res|
        break if @remaining <= 0
        fulfill_qty = [res.quantity, @remaining].min
        @remaining -= fulfill_qty
        if fulfill_qty == res.quantity
          # Asignar completamente
          res.update!(status: :assigned, assigned_at: Time.current)
          # Futuro: crear / vincular sale order aquí o notificar usuario
        else
          # Caso parcial (split). Por simplicidad marcamos asignada parcial y ajustamos.
          # Alternativa: crear una reserva nueva para remanente.
          remaining = res.quantity - fulfill_qty
          res.update!(quantity: fulfill_qty, status: :assigned, assigned_at: Time.current)
          PreorderReservation.create!(product: @product, user: res.user, quantity: remaining, status: :pending, reserved_at: Time.current)
        end
      end
    end
  end
end
