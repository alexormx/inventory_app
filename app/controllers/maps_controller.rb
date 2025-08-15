class MapsController < ApplicationController
  require 'net/http'
  require 'uri'
  require 'json'
  require 'digest'

  # Serve map GeoJSON from our domain to avoid CDN/CORS issues
  def world
    # Try local file first
    local = Rails.root.join('public', 'maps', 'world.json')
    return render_cached_file(local) if File.exist?(local)
    urls = [
      'https://fastly.jsdelivr.net/npm/echarts@5/examples/data/asset/world.json',
      'https://cdn.jsdelivr.net/npm/echarts@5/examples/data/asset/world.json',
      'https://echarts.apache.org/examples/data/asset/geo/world.json'
    ]
    proxy_json_from(urls)
  end

  def mexico
    # Try local file first
    local = Rails.root.join('public', 'maps', 'mexico.json')
    return render_cached_file(local) if File.exist?(local)
    urls = [
      'https://fastly.jsdelivr.net/npm/echarts@5/examples/data/asset/geo/MEX.json',
      'https://cdn.jsdelivr.net/npm/echarts@5/examples/data/asset/geo/MEX.json',
      # Alternate community mirrors (may not always exist)
      'https://raw.githubusercontent.com/apache/echarts/next/examples/data/asset/geo/MEX.json'
    ]
    proxy_json_from(urls)
  end

  private
  def render_cached_file(path)
    cache_key = "map_file::" + Digest::SHA1.hexdigest(path.to_s)
    cached = Rails.cache.read(cache_key)
    if cached
      response.set_header('Cache-Control', 'public, max-age=86400')
      return render json: cached
    end
    begin
      json = JSON.parse(File.read(path))
      Rails.cache.write(cache_key, json, expires_in: 24.hours)
      response.set_header('Cache-Control', 'public, max-age=86400')
      render json: json
    rescue => e
      Rails.logger.warn("Map local file error #{path}: #{e.class}: #{e.message}")
      render json: { error: 'map_unavailable' }, status: :bad_gateway
    end
  end
  def proxy_json_from(urls)
    cache_key = "map_json::" + Digest::SHA1.hexdigest(urls.join(','))
    cached = Rails.cache.read(cache_key)
    if cached
      response.set_header('Cache-Control', 'public, max-age=86400')
      return render json: cached
    end
    urls.each do |url|
      begin
        uri = URI.parse(url)
        res = Net::HTTP.get_response(uri)
        if res.is_a?(Net::HTTPSuccess)
          json = JSON.parse(res.body)
          Rails.cache.write(cache_key, json, expires_in: 24.hours)
          response.set_header('Cache-Control', 'public, max-age=86400') # 1 day
          return render json: json
        end
      rescue => e
        Rails.logger.warn("Map proxy error for #{url}: #{e.class}: #{e.message}")
      end
    end
    render json: { error: 'map_unavailable' }, status: :bad_gateway
  end
end
