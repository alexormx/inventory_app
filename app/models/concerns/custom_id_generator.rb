# frozen_string_literal: true

module CustomIdGenerator
  extend ActiveSupport::Concern

  # Método para generar un ID único con prefijo, año y mes
  def generate_unique_id(prefix, date_column = :order_date)
    date = send(date_column)
    return if date.blank?

    year  = date.year
    month = date.month
    prefix_str = "#{prefix}-#{year}#{format('%02d', month)}"
    sequence = 1

    loop do
      candidate_id = "#{prefix_str}-%03d" % sequence
      return candidate_id unless self.class.exists?(id: candidate_id)

      sequence += 1
    end
  end
end