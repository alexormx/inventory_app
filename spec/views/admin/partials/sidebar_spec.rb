# frozen_string_literal: true

require 'rails_helper'

# Auditoría de la barra lateral (2026-10-12): en "Descubrir" se iluminaban dos
# enlaces a la vez, varias páginas secundarias dejaban el menú sin contexto y
# había iconos repetidos entre secciones distintas.
RSpec.describe 'admin/partials/_sidebar.html.erb', type: :view do
  let(:admin) { build_stubbed(:user, :admin) }

  def highlighted_for(path)
    allow(view).to receive_messages(current_user: admin, request: instance_double(ActionDispatch::Request, path: path))
    render partial: 'admin/partials/sidebar'
    Nokogiri::HTML.fragment(rendered).css('a.nav-link.active, a.nav-link.section-active').map { |a| a['aria-label'] }
  end

  {
    '/admin/supplier_catalog_items/discovery' => 'Descubrir Nuevos Productos',
    '/admin/supplier_catalog_items/discovery_progress' => 'Descubrir Nuevos Productos',
    '/admin/supplier_catalog_items/42' => 'Actualizar Catálogo Proveedor',
    '/admin/supplier_catalog_review' => 'Actualizar Catálogo Proveedor',
    '/admin/payment_methods' => 'Configuración',
    '/admin/payment_methods/3/edit' => 'Configuración',
    '/admin/shipping_methods/new' => 'Configuración',
    '/admin/inventory_audit' => 'Configuración',
    '/admin/inventory_events' => 'Configuración',
    '/admin/location_types/2/edit' => 'Ubicaciones',
    '/admin/preorders_audit' => 'Preórdenes',
    '/admin/category_attribute_templates/new' => 'Enriquecimiento IA'
  }.each do |path, label|
    it "highlights only #{label.inspect} on #{path}" do
      expect(highlighted_for(path)).to eq([label])
    end
  end

  it 'gives every link its own icon' do
    highlighted_for('/admin/dashboard')
    icons = Nokogiri::HTML.fragment(rendered).css('a.nav-link i').map { |i| i['class'][/fa-(?!solid)[\w-]+/] }

    expect(icons.tally.select { |_, n| n > 1 }.keys).to be_empty
  end
end
