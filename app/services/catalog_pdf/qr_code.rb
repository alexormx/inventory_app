# frozen_string_literal: true

require 'base64'

module CatalogPdf
  # QR vectorial y autocontenido: Grover no necesita red ni rasterización.
  module QrCode
    module_function

    def data_uri(payload)
      require 'rqrcode'
      svg = RQRCode::QRCode.new(payload, level: :m).as_svg(
        color: '128C7E',
        fill: 'ffffff',
        module_size: 4,
        offset: 4,
        shape_rendering: 'crispEdges',
        use_path: true
      )
      "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
    end
  end
end
