# frozen_string_literal: true

module Admin
  module PurchaseOrdersHelper
    def status_badge_class(status)
      {
        'Pending' => 'bg-warning text-dark',
        'In Transit' => 'bg-primary',
        'Delivered' => 'bg-success',
        'Canceled' => 'bg-danger'
      }[status] || 'bg-secondary'
    end
  end
end