# frozen_string_literal: true

class SitemapsController < ApplicationController
  # No authentication required for sitemaps
  skip_before_action :authenticate_user!, raise: false

  def show
    @host = request.base_url

    # Cache the sitemap for 1 hour
    expires_in 1.hour, public: true

    respond_to do |format|
      format.xml { render layout: false }
    end
  end
end
