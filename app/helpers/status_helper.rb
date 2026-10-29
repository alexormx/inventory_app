# frozen_string_literal: true

module StatusHelper
  def status_badge_class(status)
    {
      'Pending' => 'bg-warning text-dark',
      'Confirmed' => 'bg-info',
      'Preparing' => 'bg-purple text-white',
      'Shipped' => 'bg-primary',
      'In Transit' => 'bg-primary',
      'Delivered' => 'bg-success',
      'Canceled' => 'bg-danger'
    }[status] || 'bg-secondary'
  end

  CUSTOMER_ORDER_STATUS_LABELS = {
    'Pending' => 'Pendiente',
    'Confirmed' => 'Confirmado',
    'Preparing' => 'En preparación',
    'In Transit' => 'En camino',
    'Delivered' => 'Entregado',
    'Canceled' => 'Cancelado',
    'Returned' => 'Devuelto'
  }.freeze

  # Lo que ve el cliente; el admin sigue viendo el estado interno.
  def customer_order_status_label(status)
    CUSTOMER_ORDER_STATUS_LABELS.fetch(status, status.to_s.humanize)
  end
end
