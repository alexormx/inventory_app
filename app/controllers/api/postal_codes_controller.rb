class Api::PostalCodesController < ApplicationController
  before_action :sanitize_params
  # Public endpoint (could rate-limit / authenticate if needed)
  def index
    cp = params[:cp].to_s.strip
    return render json: { error: 'invalid_cp' }, status: :unprocessable_entity unless cp.match?(/\A\d{5}\z/)

    rows = PostalCode.by_cp(cp)
    if rows.none?
      render json: { found: false, colonias: [], municipio: nil, estado: nil }
    else
      municipio = rows.first.municipality
      estado    = rows.first.state
      colonias  = rows.map(&:settlement).uniq.sort
      render json: { found: true, estado: estado, municipio: municipio, colonias: colonias }
    end
  end

  private
  def sanitize_params
    params[:cp] = params[:cp].to_s.gsub(/[^0-9]/,'') if params[:cp]
  end
end
