class MapsController < ApplicationController
  require 'net/http'
  require 'uri'
  require 'json'

  # Serve map GeoJSON from our domain to avoid CDN/CORS issues
  def world
    proxy_json('https://fastly.jsdelivr.net/npm/echarts@5/examples/data/asset/world.json')
  end

  def mexico
    proxy_json('https://fastly.jsdelivr.net/npm/echarts@5/examples/data/asset/geo/MEX.json')
  end

  private
  def proxy_json(url)
    uri = URI.parse(url)
    res = Net::HTTP.get_response(uri)
    if res.is_a?(Net::HTTPSuccess)
      response.set_header('Cache-Control', 'public, max-age=86400') # 1 day
      render json: JSON.parse(res.body)
    else
      render json: { error: 'map_unavailable' }, status: :bad_gateway
    end
  rescue => e
    Rails.logger.warn("Map proxy error: #{e.class}: #{e.message}")
    render json: { error: 'map_fetch_failed' }, status: :bad_gateway
  end
end
