# frozen_string_literal: true

module Admin
  # Guía de la API para el admin: cómo conectar KataFrame y la tabla de
  # endpoints, leída del mismo OpenAPI que sirve /api-docs (swagger/v1/swagger.yaml,
  # generado con `bin/rails rswag:specs:swaggerize`), para que no se desfase.
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

    private

    def endpoints
      doc = YAML.safe_load_file(OPENAPI_PATH)
      doc.fetch('paths', {}).flat_map do |path, operations|
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
