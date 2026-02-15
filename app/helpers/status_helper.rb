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
end