# app/validators/date_validator.rb
class DateValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    if options[:before] && value >= record.send(options[:before])
      record.errors.add(attribute, "must be before #{options[:before].to_s.humanize}")
    end

    if options[:after] && value <= record.send(options[:after])
      record.errors.add(attribute, "must be after #{options[:after].to_s.humanize}")
    end

    if options[:before_or_equal_to] && value > record.send(options[:before_or_equal_to])
      record.errors.add(attribute, "must be on or before #{options[:before_or_equal_to].to_s.humanize}")
    end

    if options[:after_or_equal_to] && value < record.send(options[:after_or_equal_to])
      record.errors.add(attribute, "must be on or after #{options[:after_or_equal_to].to_s.humanize}")
    end
  end
end
