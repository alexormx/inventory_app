# frozen_string_literal: true

# app/validators/date_validator.rb
class DateValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    record.errors.add(attribute, "must be before #{options[:before].to_s.humanize}") if options[:before] && value >= record.send(options[:before])

    record.errors.add(attribute, "must be after #{options[:after].to_s.humanize}") if options[:after] && value <= record.send(options[:after])

    if options[:before_or_equal_to] && value > record.send(options[:before_or_equal_to])
      record.errors.add(attribute, "must be on or before #{options[:before_or_equal_to].to_s.humanize}")
    end

    return unless options[:after_or_equal_to] && value < record.send(options[:after_or_equal_to])

    record.errors.add(attribute, "must be on or after #{options[:after_or_equal_to].to_s.humanize}")
  end
end
