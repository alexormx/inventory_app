FactoryBot.define do
  factory :shipment do
    association :sale_order
    tracking_number { "TRACK123" }
    carrier { "UPS" }
    estimated_delivery { Date.today }
    status { :pending }
  end
end