require 'base64'

module CatalogPdf
  # Datos de muestra para iterar el diseño del PDF sin depender de la BD ni de
  # imágenes reales. Genera placeholders SVG embebidos.
  module SampleData
    module_function

    SAMPLES = [
      { code: 'AA01', name: 'Nissan Skyline GT-R (BNR34) Patrol Car', brand: 'Takara Tomy', price: 150, badges: [] },
      { code: 'AA02', name: 'Mazda CX-60', brand: 'Takara Tomy', price: 150, badges: ['Nuevo'] },
      { code: 'AA03', name: 'Nissan Kicks', brand: 'Takara Tomy', price: 180, badges: [] },
      { code: 'AB01', name: 'Mercedes-AMG GT R', brand: 'Takara Tomy', price: 150, badges: [] },
      { code: 'AB02', name: 'Ferrari Purosangue', brand: 'Takara Tomy', price: 150, badges: ['Nuevo'] },
      { code: 'AB03', name: 'Lamborghini Huracan STO', brand: 'Takara Tomy', price: 320, badges: ['Única Pieza'] },
      { code: 'AC01', name: 'Toyota Land Cruiser 250', brand: 'Takara Tomy', price: 150, badges: ['Nuevo'] },
      { code: 'AC02', name: 'Suzuki Jimny', brand: 'Takara Tomy', price: 150, badges: [] },
      { code: 'AC03', name: 'BMW i8 (Limited color)', brand: 'Takara Tomy', price: 320, badges: ['Única Pieza'] },
      { code: 'AD01', name: 'Toyota GR Yaris', brand: 'Takara Tomy', price: 200, badges: [] },
      { code: 'AD02', name: 'Honda NSX', brand: 'Takara Tomy', price: 150, badges: [] },
      { code: 'AD03', name: 'McLaren 720S', brand: 'Takara Tomy', price: 200, badges: [] }
    ].freeze

    def items
      SAMPLES.map { |s| s.merge(category: 'Demo', image: placeholder) }
    end

    def placeholder
      svg = <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" width="300" height="220">
          <rect width="300" height="220" fill="#eef1f4"/>
          <rect x="40" y="70" width="220" height="90" rx="8" fill="#cfd6dd"/>
          <text x="150" y="180" font-family="Arial" font-size="12" fill="#aab2bb"
                text-anchor="middle">(foto del producto)</text>
        </svg>
      SVG
      "data:image/svg+xml;base64,#{Base64.strict_encode64(svg)}"
    end
  end
end
