# frozen_string_literal: true

require 'rails_helper'

# El índice de coleccionables reventaba con NoMethodError en cuanto una pieza
# tenía imagen: la vista llamaba .attached? sobre un ActiveStorage::Attachment,
# que no responde a ese método (es de la proxy de la asociación).
RSpec.describe 'Admin collectibles images', type: :request do
  let(:admin) { create(:user, :admin) }
  let(:image_path) { Rails.root.join('spec/fixtures/files/test1.png') }

  before { sign_in admin }

  def attach_png(attachable)
    attachable.attach(
      io: File.open(image_path),
      filename: 'test1.png',
      content_type: 'image/png'
    )
  end

  describe 'GET /admin/collectibles' do
    it 'renders when a collectible piece has its own image' do
      product = create(:product, skip_seed_inventory: true, product_name: 'Coleccionable Con Foto')
      inventory = create(:inventory, product: product, status: :available, item_condition: :mint)
      attach_png(inventory.piece_images)

      get admin_collectibles_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Coleccionable Con Foto')
    end

    it 'falls back to the product image when the piece has none' do
      product = create(:product, skip_seed_inventory: true, product_name: 'Coleccionable Sin Foto')
      attach_png(product.product_images)
      create(:inventory, product: product, status: :available, item_condition: :mint)

      get admin_collectibles_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Coleccionable Sin Foto')
    end

    it 'renders the placeholder when neither piece nor product has an image' do
      product = create(:product, skip_seed_inventory: true, product_name: 'Coleccionable Pelado')
      # La factory adjunta imagen por defecto; aquí interesa el caso sin ninguna.
      product.product_images.purge
      create(:inventory, product: product, status: :available, item_condition: :mint)

      get admin_collectibles_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Coleccionable Pelado')
      expect(response.body).to include('fa-regular fa-image')
    end

    it 'does not purge or detach anything just by rendering' do
      product = create(:product, skip_seed_inventory: true)
      inventory = create(:inventory, product: product, status: :available, item_condition: :mint)
      attach_png(inventory.piece_images)

      expect { get admin_collectibles_path }
        .not_to(change { ActiveStorage::Attachment.count })
      expect(inventory.reload.piece_images).to be_attached
    end
  end

  describe 'GET /admin/collectibles/:id/edit' do
    it 'renders when the product has an image' do
      product = create(:product, skip_seed_inventory: true, product_name: 'Editable Con Foto')
      attach_png(product.product_images)
      inventory = create(:inventory, product: product, status: :available, item_condition: :mint)

      get edit_admin_collectible_path(inventory)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Editable Con Foto')
    end

    it 'renders when the product has no image' do
      product = create(:product, skip_seed_inventory: true, product_name: 'Editable Sin Foto')
      inventory = create(:inventory, product: product, status: :available, item_condition: :mint)

      get edit_admin_collectible_path(inventory)

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Editable Sin Foto')
    end
  end
end
