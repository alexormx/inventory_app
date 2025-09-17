module ImageHelper
  # Renderiza un <picture> con fuentes AVIF/WebP y fallback a la imagen dada.
  # - image: nombre del archivo fallback (jpg/png) dentro de app/assets/images
  # - alt: texto alternativo
  # - html_options: opciones para la etiqueta <img> (class, loading, width, height, etc.)
  # Nota: Asumimos que existen archivos .avif y .webp con el mismo basename que la imagen fallback.
  def picture_asset_tag(image, alt:, **html_options)
    basename = image.sub(/\.(jpg|jpeg|png|gif)$/i, '')
    avif_src  = asset_path("#{basename}.avif")
    webp_src  = asset_path("#{basename}.webp")

    # asegurar defaults útiles
    html_options[:alt] = alt
    html_options[:decoding] ||= 'async'

    content_tag(:picture) do
      concat tag.source(type: 'image/avif', srcset: avif_src)
      concat tag.source(type: 'image/webp', srcset: webp_src)
      concat image_tag(image, **html_options)
    end
  end
end
