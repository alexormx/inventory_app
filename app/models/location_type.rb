# frozen_string_literal: true

class LocationType < ApplicationRecord
  has_many :inventory_locations, foreign_key: :location_type, primary_key: :code

  validates :name, presence: true, length: { maximum: 100 }
  validates :code, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 50 }
  validates :color, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :normalize_code

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :name) }

  # Default types with Spanish names
  DEFAULT_TYPES = [
    { code: 'warehouse', name: 'Bodega', icon: 'bi-building', color: 'primary', position: 0 },
    { code: 'zone', name: 'Zona', icon: 'bi-grid-3x3-gap', color: 'info', position: 1 },
    { code: 'section', name: 'Sección', icon: 'bi-layout-split', color: 'success', position: 2 },
    { code: 'aisle', name: 'Pasillo', icon: 'bi-arrow-left-right', color: 'warning', position: 3 },
    { code: 'rack', name: 'Estante', icon: 'bi-bookshelf', color: 'danger', position: 4 },
    { code: 'shelf', name: 'Anaquel', icon: 'bi-list-nested', color: 'secondary', position: 5 },
    { code: 'level', name: 'Nivel', icon: 'bi-layers', color: 'dark', position: 6 },
    { code: 'bin', name: 'Contenedor', icon: 'bi-box', color: 'primary', position: 7 },
    { code: 'position', name: 'Posición', icon: 'bi-geo-alt', color: 'info', position: 8 }
  ].freeze

  class << self
    # Seed default types if none exist
    def seed_defaults!
      return if exists?

      DEFAULT_TYPES.each do |attrs|
        create!(attrs)
      end
    end

    # Get all active type codes for validation
    def valid_codes
      active.ordered.pluck(:code)
    end

    # Get options for select dropdown
    def options_for_select
      active.ordered.pluck(:name, :code)
    end

    # Get type by code with fallback
    def find_by_code(code)
      find_by(code: code)
    end

    # Get name for a code (with fallback)
    def name_for(code)
      find_by(code: code)&.name || code.to_s.humanize
    end

    # Get color for a code (with fallback)
    def color_for(code)
      find_by(code: code)&.color || 'secondary'
    end

    # Get icon for a code (with fallback)
    def icon_for(code)
      find_by(code: code)&.icon || 'bi-geo-alt'
    end
  end

  def display_name
    "#{name} (#{code})"
  end

  private

  def normalize_code
    self.code = code.to_s.parameterize.underscore if code.present?
  end
end
