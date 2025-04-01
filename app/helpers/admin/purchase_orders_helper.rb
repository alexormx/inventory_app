module Admin::PurchaseOrdersHelper
  def status_badge_class(status)
    {
      "Pending" => "bg-warning text-dark",
      "In Transit" => "bg-primary",
      "Delivered" => "bg-success",
      "Canceled" => "bg-danger"
    }[status] || "bg-secondary"
  end
end