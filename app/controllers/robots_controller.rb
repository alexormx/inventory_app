# frozen_string_literal: true

class RobotsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def show
    expires_in 1.day, public: true

    body = <<~TXT
      User-agent: *
      Allow: /
      Disallow: /cart
      Disallow: /checkout/
      Disallow: /orders
      Disallow: /profile
      Disallow: /shipping_addresses
      Disallow: /users/
      Disallow: /admin/
      Disallow: /api/

      Sitemap: #{sitemap_url(host: request.base_url)}
    TXT

    render plain: body, content_type: 'text/plain'
  end
end
