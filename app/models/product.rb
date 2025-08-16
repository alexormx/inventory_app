class Product < ApplicationRecord
  extend FriendlyId
  friendly_id :product_name, use: :slugged

  belongs_to :preferred_supplier, class_name: "User", optional: true
  belongs_to :last_supplier, class_name: "User", optional: true

  has_many :inventories, class_name: "Inventory", foreign_key: :product_id, inverse_of: :product, dependent: :nullify
  has_many :canceled_order_items, dependent: :restrict_with_error
  has_many :purchase_order_items
  has_many :purchase_orders, through: :purchase_order_items
  has_many_attached :product_images
  has_many :sale_order_items
  has_many :sale_orders, through: :sale_order_items

  # --- Financial & status defaults ---
  after_initialize :set_default_financial_fields, if: :new_record?
  after_initialize :set_api_fallback_defaults,    if: :new_record?

  # --- Stats update on create (your logic) ---
  after_commit :recalculate_stats_if_needed, on: [:create]

  # --- Custom attributes: always a JSON Hash ---
  attribute :custom_attributes, :json, default: {}
  before_validation :normalize_custom_attributes
  before_validation :ensure_whatsapp_code
  validate :custom_attributes_must_be_object

  # --- Create enums for the product status ---
  enum :status,
      { draft: 'draft', active: 'active', inactive: 'inactive' },
      default: :draft

  # --- Validations ---
  validates :product_sku, presence: true, uniqueness: true
  validates :product_name, presence: true
  validates :selling_price, presence: true, numericality: { greater_than: 0 }
  validates :maximum_discount, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :minimum_price, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :discount_limited_stock, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :whatsapp_code, presence: true, uniqueness: true
  validate  :minimum_price_not_exceed_selling_price

  # --- Scopes ---
  scope :publicly_visible, -> { active }

  # --- Public helper for your current view (optional, can be removed later) ---
  def parsed_custom_attributes
    custom_attributes.is_a?(Hash) ? custom_attributes : {}
  end

  # NEW: Normalize at assignment time (runs earlier than validations)
  def status=(value)
    normalized = value.to_s.strip.downcase
    normalized = 'draft' if normalized.blank?
    normalized = 'inactive' unless self.class.statuses.key?(normalized)
    super(normalized)
  end

  def self.find_by_identifier!(identifier)
    find_by(id: identifier) ||
      find_by(product_sku: identifier) ||
      (column_names.include?("slug") && find_by(slug: identifier)) ||
      find_by(whatsapp_code: identifier) ||
      where("LOWER(REPLACE(product_name, ' ', '-')) = ?", identifier.to_s.downcase).first ||
      (raise ActiveRecord::RecordNotFound)
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
    self.backorder_allowed     = false if self.backorder_allowed.nil?
    self.preorder_available    = false if self.preorder_available.nil?
    self.status              ||= "draft"
    self.discount_limited_stock ||= 0
    self.reorder_point          ||= 0
  end

  # === The single source of truth for normalization ===
  def normalize_custom_attributes
    h = self.custom_attributes

    # If this came from params it might be an ActionController::Parameters
    # Convert common parameter-like objects to a plain Hash so normalization
    # logic below works consistently.
    if defined?(ActionController::Parameters) && h.is_a?(ActionController::Parameters)
      h = h.to_unsafe_h
    elsif h.respond_to?(:to_h) && !h.is_a?(Hash)
      # Try a generic conversion for other hash-like objects
      begin
        h = h.to_h
      rescue StandardError
        # fall through; will be handled below
      end
    end

    # 1) Strings -> Hash
    if h.is_a?(String)
      begin
        h = JSON.parse(h)
      rescue JSON::ParserError
        h = { "raw" => h } # preserve if unparseable
      end
    end

    # 2) Ensure a Hash
    h = {} unless h.is_a?(Hash)

    # 3) Recursively normalize (lowercase keys, ""/nan -> nil)
    self.custom_attributes = deep_normalize(h)
  end

  # Downcase keys; ""/"nan" -> nil; recurse into arrays/hashes
  def deep_normalize(obj)
    case obj
    when Hash
      obj.each_with_object({}) do |(k, v), acc|
        key = k.to_s.strip.downcase
        acc[key] = deep_normalize(v)
      end
    when Array
      obj.map { |v| deep_normalize(v) }
    when String
      s = obj.strip
      return nil if s.empty? || s.casecmp('nan').zero?
      obj
    else
      obj
    end
  end

  def custom_attributes_must_be_object
    errors.add(:custom_attributes, 'must be an object') unless custom_attributes.is_a?(Hash)
  end

  def ensure_whatsapp_code
    return if whatsapp_code.present?
    self.whatsapp_code = SecureRandom.alphanumeric(6).upcase
  end

end
