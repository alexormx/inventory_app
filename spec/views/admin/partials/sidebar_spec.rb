# frozen_string_literal: true

require 'rails_helper'

# Auditoría de la barra lateral (2026-10-12): en "Descubrir" se iluminaban dos
# enlaces a la vez, varias páginas secundarias dejaban el menú sin contexto,
# había iconos repetidos, 30 enlaces siempre visibles, ningún contador y
# mayúsculas inconsistentes.
RSpec.describe 'admin/partials/_sidebar.html.erb', type: :view do
  let(:admin) { build_stubbed(:user, :admin) }

  def render_sidebar_at(path)
    allow(view).to receive_messages(current_user: admin, request: instance_double(ActionDispatch::Request, path: path))
    render partial: 'admin/partials/sidebar'
    Nokogiri::HTML.fragment(rendered)
  end

  def labels_at(path)
    render_sidebar_at(path).css('a.nav-link .sidebar-link-label').map { |s| s.text.strip }
  end

  def highlighted_for(path)
    render_sidebar_at(path).css('a.nav-link.active, a.nav-link.section-active').map { |a| a.at_css('.sidebar-link-label').text.strip }
  end

  def badge_for(fragment, label)
    link = fragment.css('a.nav-link').find { |a| a.at_css('.sidebar-link-label').text.strip == label }
    link.at_css('.sidebar-badge')&.text&.strip
  end

  {
    '/admin/supplier_catalog_items/discovery' => ['Catálogo del proveedor', 'Descubrir nuevos productos'],
    '/admin/supplier_catalog_items/discovery_progress' => ['Catálogo del proveedor', 'Descubrir nuevos productos'],
    '/admin/supplier_catalog_items/42' => ['Catálogo del proveedor'],
    '/admin/supplier_catalog_review' => ['Catálogo del proveedor'],
    '/admin/payment_methods' => ['Configuración'],
    '/admin/payment_methods/3/edit' => ['Configuración'],
    '/admin/shipping_methods/new' => ['Configuración'],
    '/admin/inventory_audit' => ['Configuración'],
    '/admin/inventory_events' => ['Configuración'],
    '/admin/system_variables' => ['Configuración'],
    '/admin/location_types/2/edit' => ['Ubicaciones'],
    '/admin/preorders_audit' => ['Preórdenes'],
    '/admin/category_attribute_templates/new' => ['Enriquecimiento IA'],
    '/admin/catalog_review' => ['Productos', 'Revisión catálogo'],
    '/admin/inventory_verifications/7' => ['Inventario', 'Verificación física']
  }.each do |path, labels|
    it "highlights #{labels.join(' + ')} on #{path}" do
      expect(highlighted_for(path)).to eq(labels)
    end
  end

  it 'gives every link its own icon' do
    icons = render_sidebar_at('/admin/inventory').css('a.nav-link i').map { |i| i['class'][/fa-(?!solid)[\w-]+/] }

    expect(icons.tally.select { |_, n| n > 1 }.keys).to be_empty
  end

  describe 'compact navigation' do
    let(:sub_links) do
      ['Vinculación catálogo', 'Revisión catálogo', 'Agregar coleccionable', 'Descubrir nuevos productos',
       'Sin ubicación', 'Explorar ubicaciones', 'Verificación física', 'Transferir']
    end

    it 'hides section sub-links outside their section' do
      labels = labels_at('/admin/dashboard')

      expect(labels & sub_links).to be_empty
      expect(labels).not_to include('Variables del sistema')
      expect(labels.size).to be <= 22
    end

    it 'shows the sub-links of the section being visited' do
      expect(labels_at('/admin/inventory/transfer'))
        .to include('Sin ubicación', 'Explorar ubicaciones', 'Verificación física', 'Transferir')
      expect(labels_at('/admin/products/catalog_status')).to include('Vinculación catálogo', 'Revisión catálogo')
      expect(labels_at('/admin/collectibles')).to include('Agregar coleccionable')
      expect(labels_at('/admin/supplier_catalog_items')).to include('Descubrir nuevos productos')
    end

    it 'does not open the inventory sub-links on sibling inventory pages' do
      expect(labels_at('/admin/inventory_adjustments')).not_to include('Transferir')
    end
  end

  describe 'counter badges' do
    it 'counts what is waiting for the admin and hides empty counters' do
      product = create(:product, skip_seed_inventory: true)
      create_list(:user, 2).each do |author|
        Review.create!(product: product, user: author, rating: 5, body: 'Excelente pieza, llegó perfecta.')
      end
      create(:whatsapp_request, status: :sent)
      create(:whatsapp_request, status: :contacted)

      sidebar = render_sidebar_at('/admin/dashboard')

      expect(badge_for(sidebar, 'Reseñas')).to eq('2')
      expect(badge_for(sidebar, 'Pedidos WhatsApp')).to eq('1')
      expect(badge_for(sidebar, 'Comentarios')).to be_nil
    end
  end

  describe 'wording' do
    it 'uses sentence case for every link' do
      title_cased = labels_at('/admin/inventory').reject do |label|
        label.split.drop(1).none? { |word| word.match?(/\A[[:upper:]][[:lower:]]/) && word != 'WhatsApp' }
      end

      expect(title_cased).to be_empty
    end

    it 'shows the signed-in role in Spanish' do
      expect(render_sidebar_at('/admin/dashboard').at_css('.sidebar-footer').text).to include('Administrador')
    end
  end
end
