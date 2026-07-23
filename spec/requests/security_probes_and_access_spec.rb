# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Security: probe requests and admin access control', type: :request do
  before(:all) { Rails.application.reload_routes! }

  describe 'automated file/secret probes against /' do
    it 'serves the homepage (200) and ignores .env query params' do
      get '/', params: { _: 'x', v: '.env' }
      expect(response).to have_http_status(:ok)
    end

    it 'serves the homepage (200) for a config-file probe param' do
      get '/', params: { _: 'x', v: 'config/app.php' }
      expect(response).to have_http_status(:ok)
    end

    it 'does not log .env probe query strings into visitor metrics' do
      expect(VisitorLogs::TrackJob).not_to receive(:perform_later)
      get '/', params: { _: 'x', v: '.env' }
    end

    it 'does not log .php / config probe query strings' do
      expect(VisitorLogs::TrackJob).not_to receive(:perform_later)
      get '/', params: { _: 'x', v: 'config/app.php' }
    end

    it 'still logs a legitimate homepage visit' do
      expect(VisitorLogs::TrackJob).to receive(:perform_later)
      get root_path
    end
  end

  describe 'literal dotfile / config paths' do
    it 'returns 404 (no route reaches any file-reading controller)' do
      get '/.env'
      expect(response).to have_http_status(:not_found)
      get '/config/app.php'
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'admin write endpoints require authentication' do
    let(:customer) { create(:user) }
    let(:sale_order) { create(:sale_order, user: customer) }

    it 'blocks unauthenticated payment creation and redirects to login' do
      expect do
        post admin_sale_order_payments_path(sale_order), params: { payment: { amount: 100 } }
      end.not_to change(Payment, :count)
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'blocks unauthenticated shipment creation and redirects to login' do
      expect do
        post admin_sale_order_shipments_path(sale_order), params: { shipment: { carrier: 'UPS' } }
      end.not_to change(Shipment, :count)
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'blocks a non-admin (customer) from creating payments' do
      sign_in customer
      expect do
        post admin_sale_order_payments_path(sale_order), params: { payment: { amount: 100 } }
      end.not_to change(Payment, :count)
      expect(response).to redirect_to(root_path)
    end
  end
end
