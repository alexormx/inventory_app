# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AdminSidebarHelper, type: :helper do
  describe '#admin_sidebar_link' do
    before do
      allow(helper).to receive(:request).and_return(double(path: current_path))
    end

    let(:current_path) { '/admin/products' }

    it 'renders a normalized Font Awesome class for bare icon names' do
      html = helper.admin_sidebar_link('Productos', '/admin/products', icon: 'box-open')

      expect(html).to include('fa-solid fa-box-open me-2 sidebar-link-icon')
      expect(html).to include('aria-current="page"')
      expect(html).to include('title="Productos"')
    end

    it 'normalizes legacy Font Awesome icon declarations' do
      html = helper.admin_sidebar_link('Usuario', '/admin/products', icon: 'fas fa-user')

      expect(html).to include('fa-solid fa-user me-2 sidebar-link-icon')
      expect(html).not_to include('fas fa-user')
    end

    it 'marks section links active for nested paths' do
      allow(helper).to receive(:request).and_return(double(path: '/admin/inventory/transfer'))

      html = helper.admin_sidebar_link('Inventario', '/admin/inventory', icon: 'boxes-stacked', section: true)

      expect(html).to include('aria-current="page"')
    end
  end
end
