# frozen_string_literal: true

# Canonical contract for the public catalog query string.
#
# HTML forms use the conventional bracketed names for arrays (for example,
# `categories[]`), which Rails parses into the unbracketed keys listed here.
# No legacy aliases are accepted: every catalog layer reads this same set.
class CatalogQuery
  ARRAY_KEYS = %w[categories brands series conditions].freeze
  PRICE_KEYS = %w[price_min price_max].freeze
  AVAILABILITY_KEYS = %w[in_stock in_transit to_order].freeze
  SORT_VALUES = %w[newest popular reviews_desc price_asc price_desc name_asc].freeze
  DEFAULT_SORT = 'newest'

  attr_reader :q, :sort, :page, :categories, :brands, :series, :conditions,
              :price_min, :price_max

  def initialize(parameters)
    @parameters = extract_parameters(parameters)
    @q = scalar_value('q').to_s.strip
    @categories = array_value('categories')
    @brands = array_value('brands')
    @series = array_value('series')
    @conditions = array_value('conditions') & Product::CONDITION_GROUPS.keys
    @price_min = price_value('price_min')
    @price_max = price_value('price_max')
    @availability = AVAILABILITY_KEYS.index_with { |key| boolean_value(key) }

    requested_sort = scalar_value('sort')
    @sort_explicit = SORT_VALUES.include?(requested_sort)
    @sort = @sort_explicit ? requested_sort : DEFAULT_SORT
    @page = positive_integer_value('page')
  end

  def filters
    {
      categories: categories,
      brands: brands,
      series: series,
      conditions: conditions,
      price_min: price_min,
      price_max: price_max,
      in_stock: in_stock?,
      in_transit: in_transit?,
      to_order: to_order?
    }
  end

  def filter_state
    OpenStruct.new(
      selected_categories: categories,
      selected_brands: brands,
      selected_series: series,
      selected_conditions: conditions,
      price_min: price_min,
      price_max: price_max,
      in_stock_only: in_stock?,
      in_transit_only: in_transit?,
      to_order_only: to_order?,
      has_filters: filters_active?
    )
  end

  def query_parameters(except: [])
    excluded = Array(except).map(&:to_s)
    values = {}
    values['q'] = q if q.present?
    ARRAY_KEYS.each do |key|
      selected = public_send(key)
      values[key] = selected if selected.present?
    end
    PRICE_KEYS.each do |key|
      value = public_send(key)
      values[key] = value if value.present?
    end
    AVAILABILITY_KEYS.each { |key| values[key] = '1' if public_send("#{key}?") }
    values['sort'] = sort if @sort_explicit
    values['page'] = page if page.present?
    values.except(*excluded)
  end

  def in_stock?
    @availability['in_stock']
  end

  def in_transit?
    @availability['in_transit']
  end

  def to_order?
    @availability['to_order']
  end

  private

  def extract_parameters(parameters)
    raw = parameters.respond_to?(:to_unsafe_h) ? parameters.to_unsafe_h : parameters.to_h
    raw.stringify_keys
  end

  def scalar_value(key)
    value = @parameters[key]
    value if value.is_a?(String) || value.is_a?(Numeric)
  end

  def array_value(key)
    Array(@parameters[key]).filter_map do |value|
      next unless value.is_a?(String) || value.is_a?(Numeric)

      value.to_s.strip.presence
    end.uniq
  end

  def price_value(key)
    value = scalar_value(key).to_s.strip
    return if value.blank?

    decimal = BigDecimal(value, exception: false)
    value if decimal && decimal >= 0
  end

  def boolean_value(key)
    ActiveModel::Type::Boolean.new.cast(scalar_value(key))
  end

  def positive_integer_value(key)
    value = Integer(scalar_value(key), exception: false)
    value if value&.positive?
  end

  def filters_active?
    categories.any? || brands.any? || series.any? || conditions.any? ||
      price_min.present? || price_max.present? ||
      AVAILABILITY_KEYS.any? { |key| public_send("#{key}?") }
  end
end
