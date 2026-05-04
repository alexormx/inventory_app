# frozen_string_literal: true

class Product < ApplicationRecord
  extend FriendlyId
  friendly_id :product_name, use: :slugged

  WHATSAPP_CODE_FORMAT = /\A[A-Z]{2}\d{2}\z/
  MAX_WHATSAPP_CODE = 'ZZ99'

  belongs_to :preferred_supplier, class_name: 'User', optional: true
  belongs_to :last_supplier, class_name: 'User', optional: true

  has_many :inventories, class_name: 'Inventory', inverse_of: :product, dependent: :nullify
  has_many :canceled_order_items, dependent: :restrict_with_error
  has_many :purchase_order_items
  has_many :purchase_orders, through: :purchase_order_items
  has_many_attached :product_images
  has_many :sale_order_items
  has_many :sale_orders, through: :sale_order_items
  has_many :description_drafts, class_name: "ProductDescriptionDraft", dependent: :destroy
  has_one :supplier_catalog_item, dependent: :nullify
  has_one :product_catalog_review, dependent: :destroy

  # --- Financial & status defaults ---
  after_initialize :set_default_financial_fields, if: :new_record?
  after_initialize :set_api_fallback_defaults,    if: :new_record?

  before_validation :normalize_custom_attributes
  before_validation :sync_series_from_custom_attributes
  before_validation :normalize_numeric_inputs
  before_validation :normalize_whatsapp_code
  before_validation :ensure_whatsapp_code
  # --- Stats update on create (your logic) ---
  after_commit :recalculate_stats_if_needed, on: [:create]
  after_commit :recalculate_purchase_orders_if_dimensions_changed, on: [:update]

  # --- Custom attributes: always a JSON Hash ---
  attribute :custom_attributes, :json, default: -> { {} }
  attribute :highlights, :json, default: -> { [] }
  attribute :seo_keywords, :json, default: -> { [] }
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
  validates :whatsapp_code, format: { with: WHATSAPP_CODE_FORMAT, message: 'must use format AA00' }, if: :enforce_whatsapp_code_format?
  validate  :minimum_price_not_exceed_selling_price

  # --- Scopes ---
  scope :publicly_visible, -> { active }
  scope :discontinued, -> { where(discontinued: true) }
  scope :in_production, -> { where(discontinued: false) }
  # Placeholder descriptions that should be treated as "missing"
  PLACEHOLDER_DESCRIPTIONS = ["Auto a escala"].freeze

  scope :without_description, -> {
    where(description: [nil, ""] + PLACEHOLDER_DESCRIPTIONS)
  }
  scope :with_description, -> {
    where.not(description: [nil, ""] + PLACEHOLDER_DESCRIPTIONS)
  }

  # Productos con al menos un inventario en bodega (status que requieren ubicación)
  # cuya ubicación física ya fue confirmada.
  scope :with_confirmed_location, -> {
    where(id: Inventory.where(status: Inventory::STATUSES_REQUIRING_LOCATION)
                       .where.not(inventory_location_id: nil)
                       .select(:product_id))
  }
  # Productos con al menos un inventario en bodega que aún no tiene ubicación asignada.
  scope :missing_location, -> {
    where(id: Inventory.where(status: Inventory::STATUSES_REQUIRING_LOCATION,
                              inventory_location_id: nil)
                       .select(:product_id))
  }
  # Productos con al menos una pieza en estatus :available (vendible inmediato).
  scope :with_stock, -> {
    where(id: Inventory.where(status: :available).select(:product_id))
  }

  # Grupos de "Condición" para filtrar el catálogo público. La data vive en
  # Inventory.item_condition (8 valores enum); estos grupos los exponen al
  # cliente como 4 categorías más legibles. NOTA: "Nuevo" aquí se refiere a
  # la CONDICIÓN de la pieza (de línea, sellada, stock renovable), NO a que
  # el producto se haya creado recientemente.
  CONDITION_GROUPS = {
    'nuevo'         => %w[brand_new],
    'sellado'       => %w[misb moc mib],
    'coleccionable' => %w[mint loose],
    'variable'      => %w[good fair]
  }.freeze

  CONDITION_GROUP_LABELS = {
    'nuevo'         => 'Nuevo (de línea)',
    'sellado'       => 'Sellado (MISB / MOC / MIB)',
    'coleccionable' => 'Coleccionable (Mint / Loose)',
    'variable'      => 'Estado variable (Good / Fair)'
  }.freeze

  # Productos con al menos un inventario :available (sin venta asignada) cuya
  # condición cae en alguno de los grupos pasados (array de strings).
  scope :with_condition_groups, ->(groups) {
    keys = Array(groups).map(&:to_s).select { |g| CONDITION_GROUPS.key?(g) }
    next none if keys.empty?

    item_conditions = keys.flat_map { |g| CONDITION_GROUPS[g] }.uniq
    where(id: Inventory.where(status: :available, sale_order_id: nil)
                       .where(item_condition: item_conditions)
                       .select(:product_id))
  }

  # --- Public helper for your current view (optional, can be removed later) ---
  def parsed_custom_attributes
    custom_attributes.is_a?(Hash) ? custom_attributes : {}
  end

  # --- Enrichment helpers ---
  def current_draft
    description_drafts.where.not(status: [:rejected, :failed]).order(created_at: :desc).first
  end

  def description_missing?
    description.blank? || self.class::PLACEHOLDER_DESCRIPTIONS.include?(description)
  end

  def attribute_template
    CategoryAttributeTemplate.for_category(category)
  end

  def supplier_catalog_linked?
    supplier_catalog_item.present?
  end

  def ordered_product_images
    attachments = product_images.attachments.includes(:blob).to_a
    return attachments if attachments.size <= 1

    primary_attachment = attachments.find { |attachment| attachment.id == primary_product_image_attachment_id }
    return attachments unless primary_attachment

    [primary_attachment] + (attachments - [primary_attachment])
  end

  def primary_product_image
    ordered_product_images.first
  end

  def set_primary_product_image!(attachment_id)
    attachment = product_images.attachments.find(attachment_id)
    update!(primary_product_image_attachment_id: attachment.id)
    attachment
  end

  def clear_primary_product_image_if_missing!
    return if primary_product_image_attachment_id.blank?
    return if product_images.attachments.where(id: primary_product_image_attachment_id).exists?

    update_column(:primary_product_image_attachment_id, product_images.attachments.order(:created_at).pick(:id))
  end

  # Normalize at assignment time: strip/downcase, default blank to 'draft'.
  # Invalid values pass through to be caught by enum validation (raises ArgumentError).
  def status=(value)
    normalized = value.to_s.strip.downcase
    normalized = 'draft' if normalized.blank?
    super(normalized)
  end

  def self.find_by_identifier!(identifier)
    ident = identifier.to_s.strip
    # Preferir slug/SKU/whatsapp antes que ID para evitar colisiones cuando el slug inicia con números
    record = nil
    record = find_by(slug: ident) if column_names.include?('slug')
    record ||= find_by(product_sku: ident)
    record ||= find_by(whatsapp_code: ident.upcase)
    # Fallback: nombre normalizado a slug simple
    record ||= where("LOWER(REPLACE(product_name, ' ', '-')) = ?", ident.downcase).first
    # Solo usar ID si el identificador es estrictamente numérico
    record = find_by(id: ident.to_i) if record.nil? && ident.match?(/\A\d+\z/)
    record || (raise ActiveRecord::RecordNotFound)
  end

  private

  def self.generate_next_whatsapp_code!
    current_code = maximum_valid_whatsapp_code
    attempts = 0

    loop do
      candidate = next_whatsapp_code_after(current_code)
      return candidate unless exists?(whatsapp_code: candidate)

      current_code = candidate
      attempts += 1
      raise StandardError, 'No available WA codes remaining' if attempts > 1000
    end
  end

  def self.maximum_valid_whatsapp_code
    where.not(whatsapp_code: nil)
      .where("LENGTH(whatsapp_code) = 4")
      .pluck(:whatsapp_code)
      .select { |code| code.match?(WHATSAPP_CODE_FORMAT) }
      .max
  end

  def self.next_whatsapp_code_after(current_code)
    return 'AA00' if current_code.blank?
    raise StandardError, 'No available WA codes remaining' if current_code == MAX_WHATSAPP_CODE

    prefix = current_code[0, 2]
    suffix = current_code[2, 2].to_i
    return "#{prefix}#{format('%02d', suffix + 1)}" if suffix < 99

    first_letter = prefix[0]
    second_letter = prefix[1]

    if second_letter < 'Z'
      "#{first_letter}#{second_letter.succ}00"
    else
      raise StandardError, 'No available WA codes remaining' if first_letter == 'Z'

      "#{first_letter.succ}A00"
    end
  end

  def minimum_price_not_exceed_selling_price
    return unless minimum_price.present? && selling_price.present? && minimum_price > selling_price

    errors.add(:minimum_price, 'cannot be higher than the selling price')
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
    self.backorder_allowed = false if backorder_allowed.nil?
    self.preorder_available      = false if preorder_available.nil?
    self.status                ||= 'draft'
    self.discount_limited_stock ||= 0
    self.reorder_point          ||= 0
    # Defaults físicos (asegurar tras migración)
    self.weight_gr  = 50.0 if weight_gr.nil? || weight_gr.to_f <= 0
    self.length_cm  = 8.0  if length_cm.nil? || length_cm.to_f <= 0
    self.width_cm   = 4.0  if width_cm.nil? || width_cm.to_f <= 0
    self.height_cm  = 4.0  if height_cm.nil? || height_cm.to_f <= 0
  end

  # === The single source of truth for normalization ===
  def normalize_custom_attributes
    h = custom_attributes

    # 1) Strings -> Hash
    if h.is_a?(String)
      begin
        h = JSON.parse(h)
      rescue JSON::ParserError
        h = { 'raw' => h } # preserve if unparseable
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

  def sync_series_from_custom_attributes
    derived_series = parsed_custom_attributes['series'].presence || parsed_custom_attributes['serie'].presence
    self.series = derived_series if derived_series.present? && series.blank?
  end

  def normalize_numeric_inputs
    self.maximum_discount = 0 if maximum_discount.blank?
    self.discount_limited_stock = 0 if discount_limited_stock.blank?
    self.reorder_point = 0 if reorder_point.blank?
  end

  def normalize_whatsapp_code
    self.whatsapp_code = whatsapp_code.to_s.strip.upcase.presence
  end

  def ensure_whatsapp_code
    return if whatsapp_code.present?

    self.whatsapp_code = self.class.generate_next_whatsapp_code!
  rescue StandardError => e
    errors.add(:whatsapp_code, e.message)
  end

  def enforce_whatsapp_code_format?
    new_record? || will_save_change_to_whatsapp_code?
  end

  public

  # ---- Stock helpers para carrito / preorders ----
  def current_on_hand
    # Consulta simple; en vistas de lista se puede precomputar vía preload y pasar override
    @current_on_hand ||= Inventory.where(product_id: id, status: [:available]).count
  end

  # Inventario en tránsito (ya comprado, viene en camino al almacén).
  # Se considera vendible aunque no esté físicamente disponible aún.
  def in_transit_count
    @in_transit_count ||= Inventory.where(product_id: id, status: :in_transit, sale_order_id: nil).count
  end

  # Inventario disponible agrupado por condición con precio
  # Retorna: [{ condition: 'brand_new', label: 'Nuevo', count: 5, price: 150.0 }, ...]
  def available_by_condition
    @available_by_condition ||= begin
      # Agrupar inventario disponible por condición
      counts = inventories.where(status: :available)
                          .group(:item_condition)
                          .count

      # Obtener precio representativo por condición (promedio de selling_price o product price)
      prices = inventories.where(status: :available)
                          .where.not(item_condition: :brand_new)
                          .group(:item_condition)
                          .average(:selling_price)

      counts.map do |condition, count|
        condition_str = condition.to_s
        {
          condition: condition_str,
          label: Inventory::CONDITION_LABELS[condition_str] || condition_str.titleize,
          short_label: condition_short_label(condition_str),
          count: count,
          price: condition_str == 'brand_new' ? selling_price : (prices[condition]&.to_f || selling_price),
          collectible: condition_str != 'brand_new'
        }
      end.sort_by { |c| Inventory::ITEM_CONDITIONS[c[:condition].to_sym] || 99 }
    end
  end

  # ¿Tiene piezas coleccionables (no nuevas)?
  def has_collectibles?
    available_by_condition.any? { |c| c[:collectible] && c[:count].positive? }
  end

  # Total disponible (todas las condiciones)
  def total_available
    available_by_condition.sum { |c| c[:count] }
  end

  private

  def condition_short_label(condition)
    case condition
    when 'brand_new' then 'Nuevo'
    when 'misb' then 'MISB'
    when 'moc' then 'MOC'
    when 'mib' then 'MIB'
    when 'mint' then 'Mint'
    when 'loose' then 'Loose'
    when 'good' then 'Good'
    when 'fair' then 'Fair'
    else condition.titleize
    end
  end

  public

  def oversell_allowed?
    backorder_allowed || preorder_available
  end

  def supply_mode
    return :preorder if preorder_available
    return :backorder if backorder_allowed

    :stock
  end

  # Desglose de cantidades inmediata vs pendiente según flags.
  # immediate consume on_hand (available); in_transit_qty consume inventario en tránsito;
  # pending cae a preorder/backorder según flags del producto.
  def split_immediate_and_pending(requested_qty)
    splitter = InventoryServices::AvailabilitySplitter.new(self, requested_qty)
    r = splitter.call
    {
      requested: r.requested,
      on_hand: r.on_hand,
      in_transit: r.in_transit,
      immediate: r.immediate,
      in_transit_qty: r.in_transit_qty,
      pending: r.pending,
      pending_type: r.pending_type
    }
  end

  # Total vendible (lo que se puede meter al carrito / lista WA sin caer a preorder/backorder)
  def sellable_count
    current_on_hand + in_transit_count
  end

  # Inactiva el producto si no es preorderable, no es backorderable, y no tiene
  # ni stock disponible ni inventario en tránsito. Solo aplica a productos en estado :active
  # — no auto-reactiva: el admin debe reactivarlos manualmente cuando vuelva a haber stock.
  def auto_deactivate_if_unavailable!
    return unless active?
    return if preorder_available || backorder_allowed
    return if Inventory.where(product_id: id, status: %i[available in_transit]).exists?

    update_columns(status: 'inactive', updated_at: Time.current)
  end

  # ---- Dimensiones / Peso helpers ----
  # Volumen unitario en cm3 (length * width * height). Si falta algún dato retorna 0.
  def unit_volume_cm3
    return 0.to_d unless respond_to?(:length_cm) && respond_to?(:width_cm) && respond_to?(:height_cm)
    return 0.to_d if length_cm.blank? || width_cm.blank? || height_cm.blank?

    l = length_cm.to_d
    w = width_cm.to_d
    h = height_cm.to_d

    return 0.to_d if l.zero? || w.zero? || h.zero?

    l * w * h
  end

  # Peso unitario en gramos
  def unit_weight_gr
    return 0.to_d unless respond_to?(:weight_gr)
    return 0.to_d if weight_gr.blank?

    weight_gr.to_d
  end

  def recalculate_purchase_orders_if_dimensions_changed
    return unless saved_change_to_weight_gr? || saved_change_to_length_cm? || saved_change_to_width_cm? || saved_change_to_height_cm?

    if defined?(PurchaseOrders::RecalculateAllCostsForProductService)
      PurchaseOrders::RecalculateAllCostsForProductService.new(self, dimension_change: true).call
    else
      # Fallback legacy
      PurchaseOrders::RecalculateCostsForProductService.new(self).call
      PurchaseOrders::RecalculateDistributedCostsForProductService.new(self).call
    end
  end
end
