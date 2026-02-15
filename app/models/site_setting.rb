# frozen_string_literal: true

class SiteSetting < ApplicationRecord
  TYPES = %w[string boolean integer json].freeze

  validates :key, presence: true, uniqueness: true
  validates :value_type, inclusion: { in: TYPES }

  scope :by_key, ->(k) { where(key: k).limit(1) }

  def self.get(key, default = nil)
    rec = by_key(key).first
    return default unless rec

    rec.cast_value
  end

  def self.set(key, value, value_type = nil)
    value_type ||= infer_type(value)
    rec = find_or_initialize_by(key: key)
    rec.value_type = value_type
    rec.value = serialize_value(value, value_type)
    rec.save!
    rec.cast_value
  end

  def cast_value
    case value_type
    when 'boolean' then ActiveModel::Type::Boolean.new.cast(value)
    when 'integer' then value.to_i
    when 'json'    then begin
      JSON.parse(value || 'null')
    rescue StandardError
      nil
    end
    else value
    end
  end

  def self.serialize_value(val, type)
    case type
    when 'boolean' then (!!val).to_s
    when 'integer' then val.to_i.to_s
    when 'json'    then val.to_json
    else val.to_s
    end
  end

  def self.infer_type(val)
    case val
    when TrueClass, FalseClass then 'boolean'
    when Integer then 'integer'
    when Hash, Array then 'json'
    else 'string'
    end
  end
end
