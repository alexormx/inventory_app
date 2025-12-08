# frozen_string_literal: true

module Admin
  class PreordersAuditsController < ApplicationController
    before_action :authorize_admin!

    def index
      render plain: 'Preorders audit dashboard pending implementation', status: :ok
    end

    def fix
      redirect_to admin_preorders_audit_path, notice: 'Fix preorders job en cola (placeholder).'
    end
  end
end

