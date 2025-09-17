module ImageHelper
  # Renderiza un <picture> con fuentes AVIF/WebP y fallback a la imagen dada.
  # - image: nombre del archivo fallback (jpg/png) dentro de app/assets/images
  # - alt: texto alternativo
  # - html_options: opciones para la etiqueta <img> (class, loading, width, height, etc.)
  # Nota: Intentará usar .avif y .webp si existen; de lo contrario, omite esas fuentes sin fallar.
  def picture_asset_tag(image, alt:, **html_options)
    basename = image.sub(/\.(jpg|jpeg|png|gif)$/i, '')
    avif_src  = safe_asset_path("#{basename}.avif")
    webp_src  = safe_asset_path("#{basename}.webp")

    # asegurar defaults útiles
    html_options[:alt] = alt
    html_options[:decoding] ||= 'async'

    content_tag(:picture) do
      concat(tag.source(type: 'image/avif', srcset: avif_src)) if avif_src.present?
      concat(tag.source(type: 'image/webp', srcset: webp_src)) if webp_src.present?
      concat image_tag(image, **html_options)
    end
  end

  private

  # Retorna la ruta al asset si existe; nil si no existe o falla la resolución.
  def safe_asset_path(path)
    asset_path(path)
  rescue StandardError
    nil
  end
end
