# frozen_string_literal: true

module Dashboard
  # Embudo del canal WhatsApp: enviado -> contactado -> convertido.
  #
  # Se cuenta por marcas de tiempo y no por `status` porque `status` guarda una
  # sola etapa: una solicitud convertida ya no aparecería como enviada y el
  # embudo se vería vacío en la parte alta.
  class WhatsappFunnelBuilder
    def initialize(range = nil)
      @range = range
    end

    def call
      sent = scope.where.not(sent_at: nil)
      sent_count = sent.count
      contacted_count = sent.where.not(contacted_at: nil).count
      converted = sent.where.not(converted_at: nil)
      converted_count = converted.count

      {
        sent: sent_count,
        contacted: contacted_count,
        converted: converted_count,
        canceled: sent.where(status: :canceled).count,
        contact_rate: ratio(contacted_count, sent_count),
        conversion_rate: ratio(converted_count, sent_count),
        close_rate: ratio(converted_count, contacted_count),
        avg_hours_to_convert: avg_hours_to_convert(converted),
        converted_revenue: converted_revenue(converted),
        pipeline_estimate: sent.where(converted_at: nil, status: %i[sent contacted]).sum(:total_estimate).to_d
      }
    end

    private

    attr_reader :range

    def scope
      range ? WhatsappRequest.where(sent_at: range) : WhatsappRequest.all
    end

    def ratio(numerator, denominator)
      return nil unless denominator.to_i.positive?

      numerator.to_d / denominator.to_d
    end

    def avg_hours_to_convert(converted)
      seconds = converted.average(
        Arel.sql('EXTRACT(EPOCH FROM (converted_at - sent_at))')
      )
      return nil if seconds.blank?

      (seconds.to_d / 3600).round(1)
    end

    # Se prefiere el valor real de la orden generada; total_estimate es solo el
    # estimado que vio el cliente antes de que el admin ajustara precios.
    def converted_revenue(converted)
      SaleOrder.where(id: converted.select(:sale_order_id))
               .where.not(status: 'Canceled')
               .sum(:total_order_value).to_d
    end
  end
end
