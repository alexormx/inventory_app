# frozen_string_literal: true

class InventoryLocation < ApplicationRecord
  # ============================================
  # HIERARCHICAL RELATIONSHIPS
  # ============================================
  belongs_to :parent, class_name: 'InventoryLocation', optional: true
  has_many :children, class_name: 'InventoryLocation', foreign_key: :parent_id, dependent: :destroy

  # Future: relate inventories to locations
  # has_many :inventories

  # ============================================
  # LOCATION TYPES (configurable hierarchy)
  # ============================================
  LOCATION_TYPES = %w[
    warehouse
    zone
    section
    aisle
    rack
    shelf
    level
    bin
    position
  ].freeze

  # Human-readable names in Spanish
  LOCATION_TYPE_NAMES = {
    'warehouse' => 'Bodega',
    'zone' => 'Zona',
    'section' => 'Sección',
    'aisle' => 'Pasillo',
    'rack' => 'Estante',
    'shelf' => 'Anaquel',
    'level' => 'Nivel',
    'bin' => 'Contenedor',
    'position' => 'Posición'
  }.freeze

  # ============================================
  # VALIDATIONS
  # ============================================
  validates :name, presence: true, length: { maximum: 100 }
  validates :code, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 50 }
  validates :location_type, presence: true, inclusion: { in: LOCATION_TYPES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true

  # Prevent circular references
  validate :parent_cannot_be_self
  validate :parent_cannot_be_descendant

  # ============================================
  # CALLBACKS
  # ============================================
  before_validation :generate_code, on: :create, if: -> { code.blank? }
  before_save :update_depth
  after_save :update_path_cache
  after_save :update_children_path_cache, if: :saved_change_to_name?

  # ============================================
  # SCOPES
  # ============================================
  scope :active, -> { where(active: true) }
  scope :roots, -> { where(parent_id: nil) }
  scope :by_type, ->(type) { where(location_type: type) }
  scope :ordered, -> { order(:position, :name) }
  scope :with_children_count, -> {
    left_joins(:children)
      .group(:id)
      .select('inventory_locations.*, COUNT(children_inventory_locations.id) as children_count')
  }

  # ============================================
  # INSTANCE METHODS
  # ============================================

  # Get all ancestors from root to parent
  def ancestors
    return [] if parent_id.nil?

    ancestors_list = []
    current = parent
    while current
      ancestors_list.unshift(current)
      current = current.parent
    end
    ancestors_list
  end

  # Get all descendants (children, grandchildren, etc.)
  def descendants
    children.flat_map { |child| [child] + child.descendants }
  end

  # Full path as array of locations
  def path
    ancestors + [self]
  end

  # Full path as string
  def full_path
    path.map(&:name).join(' > ')
  end

  # Human-readable type name
  def type_name
    LOCATION_TYPE_NAMES[location_type] || location_type.humanize
  end

  # Display name with type
  def display_name
    "#{type_name}: #{name}"
  end

  # Check if this location is a root (no parent)
  def root?
    parent_id.nil?
  end

  # Check if this location has children
  def has_children?
    children.exists?
  end

  # Check if this location is a leaf (no children)
  def leaf?
    !has_children?
  end

  # Get siblings (other children of same parent)
  def siblings
    if parent_id
      parent.children.where.not(id: id)
    else
      self.class.roots.where.not(id: id)
    end
  end

  # Move position within siblings
  def move_to(new_position)
    update(position: new_position)
  end

  # Suggested child types based on current type
  def suggested_child_types
    current_index = LOCATION_TYPES.index(location_type) || -1
    LOCATION_TYPES[(current_index + 1)..]
  end

  # ============================================
  # CLASS METHODS
  # ============================================

  # Build a nested tree structure for UI
  def self.tree(scope = active.ordered)
    scope.roots.ordered.map { |root| build_tree_node(root, scope) }
  end

  def self.build_tree_node(location, scope)
    {
      id: location.id,
      name: location.name,
      code: location.code,
      type: location.location_type,
      type_name: location.type_name,
      depth: location.depth,
      active: location.active,
      children: location.children.ordered.map { |child| build_tree_node(child, scope) }
    }
  end

  # Flat list with indentation for select dropdowns
  def self.nested_options(scope = active.ordered)
    result = []
    scope.roots.ordered.each do |root|
      add_nested_options(root, result, 0)
    end
    result
  end

  def self.add_nested_options(location, result, depth)
    prefix = '—' * depth
    label = depth.positive? ? "#{prefix} #{location.name}" : location.name
    result << [label, location.id]
    location.children.ordered.each do |child|
      add_nested_options(child, result, depth + 1)
    end
  end

  private

  def generate_code
    base = name.to_s.parameterize.upcase.first(10)
    base = location_type.to_s.first(3).upcase if base.blank?
    base = 'LOC' if base.blank?

    # Add parent code prefix if has parent
    prefix = parent&.code.present? ? "#{parent.code}-" : ''

    # Find unique code
    candidate = "#{prefix}#{base}"
    counter = 1
    while self.class.exists?(code: candidate)
      candidate = "#{prefix}#{base}-#{counter}"
      counter += 1
    end
    self.code = candidate
  end

  def update_depth
    self.depth = parent ? parent.depth + 1 : 0
  end

  def update_path_cache
    new_path = full_path
    update_column(:path_cache, new_path) if path_cache != new_path
  end

  def update_children_path_cache
    children.find_each(&:save) # Triggers path_cache update recursively
  end

  def parent_cannot_be_self
    return unless id.present? && parent_id.present?

    errors.add(:parent_id, 'no puede ser la misma ubicación') if parent_id == id
  end

  def parent_cannot_be_descendant
    return unless parent_id.present? && id.present?

    if descendants.map(&:id).include?(parent_id)
      errors.add(:parent_id, 'no puede ser un descendiente de esta ubicación')
    end
  end
end

