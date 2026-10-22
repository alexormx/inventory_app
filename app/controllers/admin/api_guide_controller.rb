# frozen_string_literal: true

module Admin
  # Guía de la API para el admin: cómo conectar KataFrame y la tabla de
  # endpoints y la referencia interactiva (Swagger UI), todo leído del mismo
  # OpenAPI (swagger/v1/swagger.yaml, generado con `bin/rails rswag:specs:swaggerize`),
  # para que no se desfase.
  class ApiGuideController < ApplicationController
    before_action :authenticate_user!
    before_action :authorize_admin!

    OPENAPI_PATH = Rails.root.join('swagger/v1/swagger.yaml')
    VERBS = %w[get post put patch delete].freeze
    Endpoint = Data.define(:verb, :path, :summary, :tag, :permisos)

    def show
      @endpoints = endpoints
      @scope_labels = ApiKeysController::SCOPE_LABELS
    end

    def reference; end

    # El OpenAPI apuntando al host actual, para que «Try it out» llame a este
    # mismo servidor (producción, local o el dominio herokuapp).
    def openapi
      render json: openapi_doc.merge('servers' => [{ 'url' => request.base_url }])
    end

    private

    def openapi_doc
      YAML.safe_load_file(OPENAPI_PATH)
    end

    def endpoints
      openapi_doc.fetch('paths', {}).flat_map do |path, operations|
        operations.slice(*VERBS).map do |verb, op|
          Endpoint.new(verb: verb.upcase, path: path, summary: op['summary'],
                       tag: Array(op['tags']).first, permisos: Array(op['x-permisos']))
        end
      end
    rescue Errno::ENOENT
      []
    end
  end
end
