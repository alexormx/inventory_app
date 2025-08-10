class Product < ApplicationRecord
  extend FriendlyId
  friendly_id :product_name, use: :slugged
  belongs_to :preferred_supplier, class_name: "User", optional: true
  belongs_to :last_supplier, class_name: "User", optional: true
  after_commit :recalculate_stats_if_needed, on: [:create]
  after_initialize :set_api_fallback_defaults, if: :new_record?


  has_many :inventory, dependent: :restrict_with_error
  has_many :canceled_order_items, dependent: :restrict_with_error
  has_many :purchase_order_items
  has_many :purchase_orders, through: :purchase_order_items
  has_many_attached :product_images
  has_many :sale_order_items
  has_many :sale_orders, through: :sale_order_items

  validates :product_sku, presence: true, uniqueness: true
  validates :product_name, presence: true
  validates :selling_price, presence: true, numericality: { greater_than: 0 }
  validates :maximum_discount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :minimum_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :discount_limited_stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :whatsapp_code, presence: true, uniqueness: true
  validates :description, presence: true, length: { minimum: 10 }, if: -> { status == 'active' }

  validate :minimum_price_not_exceed_selling_price

  def parsed_custom_attributes
    return {} unless custom_attributes.present?

    if custom_attributes.is_a?(String)
      JSON.parse(custom_attributes)
    else
      custom_attributes
    end
  rescue JSON::ParserError
    {}
  end

  private

  def minimum_price_not_exceed_selling_price
    if minimum_price.present? && selling_price.present? && minimum_price > selling_price
      errors.add(:minimum_price, "cannot be higher than the selling price")
    end
  end

  def recalculate_stats_if_needed
    Products::UpdateStatsService.new(self).call if saved_change_to_total_purchase_quantity?
  end

  after_initialize :set_default_financial_fields, if: :new_record?

  def set_default_financial_fields
    self.total_purchase_quantity     ||= 0
    self.total_purchase_value        ||= 0.0
    self.average_purchase_cost       ||= 0.0
    self.last_purchase_cost          ||= 0.0

    self.total_sales_quantity        ||= 0
    self.total_sales_value           ||= 0.0
    self.average_sales_price         ||= 0.0
    self.last_sales_price            ||= 0.0

    self.total_purchase_order        ||= 0
    self.total_sales_order           ||= 0
    self.total_units_sold            ||= 0

    self.current_profit              ||= 0.0
    self.current_inventory_value     ||= 0.0
    self.projected_sales_value       ||= 0.0
    self.projected_profit            ||= 0.0
  end

  def set_api_fallback_defaults
    self.backorder_allowed = false if self.backorder_allowed.nil?
    self.preorder_available = false if self.preorder_available.nil?
    self.status ||= "inactive"  # Only set if nil
    self.discount_limited_stock ||= 0
    self.reorder_point ||= 0
  end

end
