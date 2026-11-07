# frozen_string_literal: true

module Finance
  # Pagos que cuentan como dinero recibido (un reembolso posterior no
  # des-concluye una venta).
  RECEIVED_PAYMENT_STATUSES = %w[Completed Refunded].freeze

  module_function

  # Fecha local (Time.zone) de una columna datetime guardada en UTC.
  def local_date_sql(column)
    tz = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.name)
    "((#{column}) AT TIME ZONE 'UTC' AT TIME ZONE #{tz})::date"
  end
end
