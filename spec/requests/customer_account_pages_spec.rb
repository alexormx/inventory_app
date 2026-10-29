# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Customer account pages', type: :request do
  let(:customer) { create(:user, name: 'Ana Cliente') }
  let!(:order) { create(:sale_order, user: customer, status: 'Pending', total_order_value: 150) }

  before { sign_in customer }

  def page_doc = Nokogiri::HTML(response.body)

  describe 'order list' do
    it 'shows each order with its status in Spanish and one link to its detail' do
      get orders_path

      row = page_doc.at_css("[data-order-id='#{order.id}']")
      expect(row.text).to include('Pendiente')
      expect(row.text).not_to include('Pending')
      expect(row['href']).to eq(order_path(order))
      expect(response.body).not_to include(summary_order_path(order))
    end

    it 'tells the customer how much is left to pay' do
      get orders_path

      owed = ActiveSupport::NumberHelper.number_to_currency(order.reload.total_order_value)
      expect(page_doc.at_css("[data-order-id='#{order.id}']").text.squish).to include("Por pagar #{owed}")
    end
  end

  describe 'order detail' do
    it 'is a single view with the products, totals and payment status' do
      get order_path(order)

      expect(response.body).to include('Estado de pago', 'Total', 'Resta por pagar')
      expect(response.body).not_to include('Ver resumen compacto', 'Ver detalle completo')
    end

    it 'keeps old compact links working with the same view' do
      get summary_order_path(order)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Estado de pago')
    end
  end

  describe 'account navigation' do
    it 'shows the same section tabs on every account page' do
      [profile_path, orders_path, order_path(order), favorites_path, edit_profile_path].each do |path|
        get path

        tabs = page_doc.css('nav.account-nav a').map { |a| a.text.squish }
        expect(tabs).to eq(['Mi perfil', 'Mis pedidos', 'Favoritos']), "missing tabs on #{path}"
      end
    end

    it 'marks the current section' do
      get orders_path

      expect(page_doc.at_css('nav.account-nav a.active').text.squish).to eq('Mis pedidos')
    end

    it 'gives every account menu entry an icon and shows who is signed in' do
      get profile_path

      menu = page_doc.at_css('#account-menu')
      expect(menu.text).to include('Ana Cliente', customer.email)
      entries = menu.css('a.dropdown-item, button.dropdown-item')
      expect(entries.map { |e| e.text.squish }).to include('Mi perfil', 'Mis pedidos', 'Mis favoritos', 'Cerrar sesión')
      expect(entries).to all(satisfy { |e| e.at_css('i.fa-solid, i.fas') })
    end
  end
end
