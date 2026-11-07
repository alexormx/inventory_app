# frozen_string_literal: true

module Finance
  # Pagos que cuentan como dinero recibido (un reembolso posterior no
  # des-concluye una venta).
  RECEIVED_PAYMENT_STATUSES = %w[Completed Refunded].freeze
end
