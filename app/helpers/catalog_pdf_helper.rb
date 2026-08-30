# frozen_string_literal: true

# Formato de la fecha de lanzamiento en las tarjetas del PDF.
module CatalogPdfHelper
  # Acepta lo que llega de cualquiera de las dos fuentes: la local entrega un
  # String ISO 8601 y la remota el mismo String tal cual salió de la API. Se
  # devuelve nil ante cualquier valor ausente o ilegible para que la vista
  # simplemente omita la línea en vez de imprimir basura.
  def catalog_pdf_launch_date(value)
    return if value.blank?

    parsed = parse_launch_value(value)
    parsed&.strftime('%d/%m/%Y')
  end

  private

  def parse_launch_value(value)
    return value if value.respond_to?(:strftime)

    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
