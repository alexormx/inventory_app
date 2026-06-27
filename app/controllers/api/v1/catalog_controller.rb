# frozen_string_literal: true

module Api
  module V1
    # Provee los datos del catálogo (productos con ubicación confirmada) para el
    # generador de PDF que corre en local. Devuelve metadata + URL de imagen;
    # el generador local descarga las imágenes y arma el PDF.
    class CatalogController < ApplicationController
      include ActionController::Live

      skip_before_action :verify_authenticity_token
      before_action :authenticate_with_token!

      # Hace stream del JSON ítem por ítem en vez de armar todo el arreglo y
      # serializarlo de una sola vez. Junto con `find_each` (lotes), el pico de
      # memoria por petición queda acotado, evitando los R14/R15 en el dyno Basic.
      def index
        response.headers['Content-Type'] = 'application/json'
        response.headers['Cache-Control'] = 'no-cache' # evita que Rack::ETag buffer-ee toda la respuesta

        stream = response.stream
        stream.write('{"items":[')
        first = true
        CatalogPdf::ProductSource.each_payload(url_builder: self) do |item|
          stream.write(',') unless first
          first = false
          stream.write(item.to_json)
        end
        stream.write(']}')
      ensure
        stream&.close
      end
    end
  end
end
