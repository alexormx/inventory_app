# frozen_string_literal: true

# rubocop:disable RSpec/ExampleLength, RSpec/MultipleExpectations

require 'rails_helper'

RSpec.describe AdminSidebarHelper, type: :helper do
  describe '#admin_sidebar_link' do
    before do
      allow(helper).to receive(:request).and_return(request_double)
    end

    let(:current_path) { '/admin/products' }
    let(:fullpath) { current_path }
    let(:request_double) { instance_double(ActionDispatch::Request, path: current_path, fullpath: fullpath) }

    def rendered_link(path = '/admin/products', section: false, icon: 'box-open')
      fragment = Nokogiri::HTML.fragment(
        helper.admin_sidebar_link('Productos', path, icon: icon, section: section)
      )
      fragment.at_css('a')
    end

    it 'marks an exact index match as the current page' do
      link = rendered_link

      expect(link['class']).to include('active')
      expect(link['aria-current']).to eq('page')
    end

    it 'keeps a resource section active on show pages without claiming the parent is the current page' do
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, path: '/admin/products/42'))

      link = rendered_link(section: true)

      expect(link['class']).to include('section-active')
      expect(link['aria-current']).to be_nil
    end

    it 'keeps a resource section active on new pages' do
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, path: '/admin/products/new'))

      expect(rendered_link(section: true)['class']).to include('section-active')
    end

    it 'keeps a resource section active on edit pages' do
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, path: '/admin/products/42/edit'))

      expect(rendered_link(section: true)['class']).to include('section-active')
    end

    it 'does not use a fragile prefix match for sibling resources' do
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, path: '/admin/inventory_adjustments'))

      link = rendered_link('/admin/inventory', section: true)

      expect(link['class']).not_to include('section-active')
      expect(link['aria-current']).to be_nil
    end

    it 'gives exact inventory children priority over their parent' do
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, path: '/admin/inventory/unlocated'))

      parent = rendered_link('/admin/inventory', section: true)
      child = rendered_link('/admin/inventory/unlocated', section: true)

      expect(parent['class']).to include('section-active')
      expect(parent['aria-current']).to be_nil
      expect(child['class']).to include('active')
      expect(child['aria-current']).to eq('page')
    end

    it 'emits only one current page for an inventory parent and child' do
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, path: '/admin/inventory/transfer'))

      html = [
        helper.admin_sidebar_link('Inventario', '/admin/inventory', icon: 'boxes-stacked', section: true),
        helper.admin_sidebar_link('Transferir', '/admin/inventory/transfer', icon: 'right-left', section: true)
      ].join

      expect(Nokogiri::HTML.fragment(html).css('a[aria-current="page"]').count).to eq(1)
    end

    it 'preserves the settings context on nested settings routes' do
      allow(helper).to receive(:request).and_return(
        instance_double(ActionDispatch::Request, path: '/admin/settings/delivered_orders_debt_audit')
      )

      link = rendered_link('/admin/settings', section: true, icon: 'gears')

      expect(link['class']).to include('section-active')
      expect(link['aria-current']).to be_nil
    end

    it 'uses request.path so query parameters do not affect the current state' do
      allow(helper).to receive(:request).and_return(
        instance_double(
          ActionDispatch::Request,
          path: '/admin/products',
          fullpath: '/admin/products?page=2&status=active'
        )
      )

      expect(rendered_link['aria-current']).to eq('page')
    end

    it 'renders a normalized Font Awesome class and an explicit accessible name' do
      link = rendered_link

      expect(link.at_css('i')['class']).to include('fa-solid fa-box-open')
      expect(link['aria-label']).to eq('Productos')
      expect(link['title']).to eq('Productos')
    end

    it 'normalizes legacy Font Awesome icon declarations' do
      link = rendered_link(icon: 'fas fa-user')

      expect(link.at_css('i')['class']).to include('fa-solid fa-user')
      expect(link.at_css('i')['class']).not_to include('fas')
    end
  end
end

# rubocop:enable RSpec/ExampleLength, RSpec/MultipleExpectations
