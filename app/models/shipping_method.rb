# frozen_string_literal: true

class ShippingMethod < ApplicationRecord
  validates :name, presence: true
  validates :code, presence: true, uniqueness: true
  validates :base_cost, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, name: :asc) }

  before_validation :normalize_code

  def self.for_select
    active.ordered.pluck(:name, :code)
  end

  def display_name
    base_cost.to_f.positive? ? "#{name} (+#{ActionController::Base.helpers.number_to_currency(base_cost)})" : name
  end

  private

  def normalize_code
    self.code = code.to_s.parameterize.underscore if code.present?
  end
end
