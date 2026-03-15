# frozen_string_literal: true

class CategoryAttributeTemplate < ApplicationRecord
  validates :category, presence: true, uniqueness: { case_sensitive: false }
  validates :attributes_schema, presence: true

  scope :active, -> { where(active: true) }

  before_validation :normalize_category

  def self.for_category(category_name)
    active.find_by(category: category_name&.downcase&.strip)
  end

  # Returns array of attribute key strings
  def attribute_keys
    attributes_schema.map { |attr| attr["key"] }
  end

  # Returns array of required attribute key strings
  def required_keys
    attributes_schema.select { |attr| attr["required"] }.map { |attr| attr["key"] }
  end

  # Returns the schema entry for a specific key
  def schema_for(key)
    attributes_schema.find { |attr| attr["key"] == key.to_s }
  end

  private

  def normalize_category
    self.category = category&.downcase&.strip
  end
end
