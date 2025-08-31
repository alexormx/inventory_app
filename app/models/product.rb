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
  after_commit :recalculate_purchase_orders_if_dimensions_changed, on: [:update]

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
    ident = identifier.to_s.strip
    # Preferir slug/SKU/whatsapp antes que ID para evitar colisiones cuando el slug inicia con números
    record = nil
    if column_names.include?("slug")
      record = find_by(slug: ident)
    end
    record ||= find_by(product_sku: ident)
    record ||= find_by(whatsapp_code: ident)
    # Fallback: nombre normalizado a slug simple
    record ||= where("LOWER(REPLACE(product_name, ' ', '-')) = ?", ident.downcase).first
    # Solo usar ID si el identificador es estrictamente numérico
    if record.nil? && ident.match?(/\A\d+\z/)
      record = find_by(id: ident.to_i)
    end
    record || (raise ActiveRecord::RecordNotFound)
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
  self.backorder_allowed       = false if self.backorder_allowed.nil?
  self.preorder_available      = false if self.preorder_available.nil?
  self.status                ||= "draft"
  self.discount_limited_stock ||= 0
  self.reorder_point          ||= 0
  # Defaults físicos (asegurar tras migración)
  self.weight_gr  = 50.0 if self.weight_gr.nil? || self.weight_gr.to_f <= 0
  self.length_cm  = 8.0  if self.length_cm.nil? || self.length_cm.to_f <= 0
  self.width_cm   = 4.0  if self.width_cm.nil? || self.width_cm.to_f <= 0
  self.height_cm  = 4.0  if self.height_cm.nil? || self.height_cm.to_f <= 0
  end

  # === The single source of truth for normalization ===
  def normalize_custom_attributes
    h = self.custom_attributes

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

  public

  # ---- Stock helpers para carrito / preorders ----
  def current_on_hand
  # Consulta simple; en vistas de lista se puede precomputar vía preload y pasar override
  @current_on_hand ||= Inventory.where(product_id: id, status: [:available]).count
  end

  def oversell_allowed?
    backorder_allowed || preorder_available
  end

  def supply_mode
    return :preorder if preorder_available
    return :backorder if backorder_allowed
    :stock
  end

  # Desglose de cantidades inmediata vs pendiente según flags
  def split_immediate_and_pending(requested_qty)
    requested = requested_qty.to_i
    on_hand = current_on_hand
    immediate = [requested, on_hand].min
    pending  = requested - immediate
    type = nil
    if pending > 0
      type = if preorder_available
               :preorder
             elsif backorder_allowed
               :backorder
             end
    end
    { requested: requested, on_hand: on_hand, immediate: immediate, pending: pending, pending_type: type }
  end

  # ---- Dimensiones / Peso helpers ----
  # Volumen unitario en cm3 (length * width * height). Si falta algún dato retorna 0.
  def unit_volume_cm3
    return 0.to_d unless respond_to?(:length_cm) && respond_to?(:width_cm) && respond_to?(:height_cm)
    l = length_cm.to_d
    return 0.to_d if length_cm.blank? || width_cm.blank? || height_cm.blank?
    l = length_cm.to_d
    w = width_cm.to_d
    h = height_cm.to_d
    return 0.to_d if l.zero? || w.zero? || h.zero?
    (l * w * h)
  end

  # Peso unitario en gramos
  def unit_weight_gr
    return 0.to_d unless respond_to?(:weight_gr)
    return 0.to_d if weight_gr.blank?
    weight_gr.to_d
  end

  def recalculate_purchase_orders_if_dimensions_changed
    if saved_change_to_weight_gr? || saved_change_to_length_cm? || saved_change_to_width_cm? || saved_change_to_height_cm?
      PurchaseOrders::RecalculateCostsForProductService.new(self).call
    end
  end
end
