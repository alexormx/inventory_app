# frozen_string_literal: true

module Api
  class PostalCodesController < ApplicationController
    skip_before_action :track_visitor
    protect_from_forgery with: :null_session

    # GET /api/postal_codes?cp=XXXXX
    def index
      cp = params[:cp].to_s.strip
      if cp.present?
        results = PostalCode.where(cp: cp).limit(20)
        render json: results.map { |r| { cp: r.cp, state: r.state, municipality: r.municipality, settlement: r.settlement } }
      else
        render json: []
      end
    end

    def show
      cp = params[:id].to_s.strip
      record = PostalCode.find_by(cp: cp)
      if record
        render json: {
          cp: record.cp,
          state: record.state,
          municipality: record.municipality,
          settlement: record.settlement,
          settlement_type: record.settlement_type
        }
      else
        render json: { error: 'Not Found' }, status: :not_found
      end
    end
  end
end

