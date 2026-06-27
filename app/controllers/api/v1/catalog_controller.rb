# frozen_string_literal: true

module Api
  module V1
    # Provee los datos del catálogo (productos con ubicación confirmada) para el
    # generador de PDF que corre en local. Devuelve metadata + URL de imagen;
    # el generador local descarga las imágenes y arma el PDF.
    class CatalogController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_with_token!

      def index
        render json: { items: CatalogPdf::ProductSource.payload(url_builder: self) }, status: :ok
      end
    end
  end
end
