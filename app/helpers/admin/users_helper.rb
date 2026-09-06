# frozen_string_literal: true

module Admin
  module UsersHelper
    ROLE_BADGE_CLASSES = { 'admin' => 'bg-danger', 'supplier' => 'bg-info', 'customer' => 'bg-primary' }.freeze
    ROLE_ICONS = { 'admin' => 'shield-alt', 'supplier' => 'truck', 'customer' => 'user' }.freeze
    CREDIT_TERMS_LABELS = { 'net15' => '15 días', 'net30' => '30 días', 'net45' => '45 días',
                            'none' => 'Sin plazo' }.freeze
    # Claves con la capitalización real de SaleOrder#status (ver StatusHelper#status_badge_class,
    # ya usado en app/views/admin/sale_orders/show.html.erb con estos mismos valores/colores).
    SALE_ORDER_STATUS_BADGE_CLASSES = { 'Pending' => 'bg-warning text-dark', 'Confirmed' => 'bg-info',
                                        'Preparing' => 'bg-purple text-white', 'In Transit' => 'bg-primary',
                                        'Delivered' => 'bg-success', 'Canceled' => 'bg-danger' }.freeze
    PURCHASE_ORDER_STATUS_COLORS = { 'draft' => 'secondary', 'ordered' => 'warning', 'in_transit' => 'info',
                                     'received' => 'success', 'cancelled' => 'danger' }.freeze
    PAYMENT_STATUS_BADGE_CLASSES = { 'Pending' => 'bg-warning text-dark', 'Completed' => 'bg-success',
                                     'Failed' => 'bg-danger', 'Refunded' => 'bg-secondary' }.freeze
    SHIPMENT_STATUS_BADGE_CLASSES = { 'pending' => 'bg-secondary', 'shipped' => 'bg-primary',
                                      'delivered' => 'bg-success', 'canceled' => 'bg-danger',
                                      'returned' => 'bg-warning text-dark' }.freeze

    def admin_user_initials(user)
      user.name.to_s.split.map(&:first).join.upcase[0, 2].presence || '?'
    end

    def admin_user_role_badge_class(role)
      ROLE_BADGE_CLASSES[role] || 'bg-secondary'
    end

    def admin_user_role_icon(role)
      ROLE_ICONS[role] || 'user'
    end

    def admin_credit_terms_label(terms)
      CREDIT_TERMS_LABELS[terms.to_s] || 'Habilitado'
    end

    def sale_order_status_badge_class(status)
      SALE_ORDER_STATUS_BADGE_CLASSES[status] || 'bg-secondary'
    end

    def purchase_order_status_badge_color(status)
      PURCHASE_ORDER_STATUS_COLORS[status] || 'secondary'
    end

    def payment_status_badge_class(status)
      PAYMENT_STATUS_BADGE_CLASSES[status] || 'bg-secondary'
    end

    def shipment_status_badge_class(status)
      SHIPMENT_STATUS_BADGE_CLASSES[status] || 'bg-secondary'
    end

    # order.balance ya viene precargado por el scope with_balance (o se calcula
    # bajo demanda) desde SaleOrder#balance; aquí solo derivamos las dos
    # cantidades de presentación a partir de ese valor canónico.
    def sale_order_paid_amount(order)
      order.total_order_value.to_d - order.balance
    end

    def sale_order_pending_amount(order)
      [order.balance, 0].max
    end
  end
end
