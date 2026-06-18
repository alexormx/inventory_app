require 'rails_helper'

RSpec.describe Product, type: :model do
  describe "Validations" do
    it { should validate_presence_of(:product_sku) }
    it { should validate_presence_of(:product_name) }
    it { should validate_presence_of(:selling_price) }
    it { should validate_numericality_of(:selling_price).is_greater_than(0) }
    it { should validate_numericality_of(:maximum_discount).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:minimum_price).is_greater_than_or_equal_to(0) }
  end

  describe 'whatsapp_code' do
    it 'requires uniqueness of whatsapp_code' do
      code = 'AB12'
      # Create first product directly (skip factory callbacks that may introduce duplicates)
      Product.create!(
        product_sku: "SKU-UNIQ-#{SecureRandom.hex(4)}",
        product_name: 'Uniq Name A',
        brand: 'BrandX',
        category: 'diecast',
        whatsapp_code: code,
        selling_price: 100,
        minimum_price: 50,
        maximum_discount: 0
      )
      dup = Product.new(
        product_sku: "SKU-UNIQ-#{SecureRandom.hex(4)}",
        product_name: 'Uniq Name B',
        brand: 'BrandX',
        category: 'diecast',
        whatsapp_code: code,
        selling_price: 100,
        minimum_price: 50,
        maximum_discount: 0
      )
      expect(dup).not_to be_valid
      expect(dup.errors[:whatsapp_code]).to be_present
    end

    it "auto-generates whatsapp_code when blank" do
      create(:product, whatsapp_code: 'AA99')

      product = Product.new(
        product_sku: "SKU-UNIQ-#{SecureRandom.hex(4)}",
        product_name: 'Name C',
        brand: 'BrandY',
        category: 'diecast',
        whatsapp_code: nil,
        selling_price: 100,
        minimum_price: 50,
        maximum_discount: 0
      )
      expect(product.valid?).to be true
      expect(product.whatsapp_code).to eq('AB00')
    end

    it 'normalizes whatsapp_code to uppercase' do
      product = Product.new(
        product_sku: "SKU-UNIQ-#{SecureRandom.hex(4)}",
        product_name: 'Name D',
        brand: 'BrandZ',
        category: 'diecast',
        whatsapp_code: 'ab12',
        selling_price: 100,
        minimum_price: 50,
        maximum_discount: 0
      )

      expect(product).to be_valid
      expect(product.whatsapp_code).to eq('AB12')
    end

    it 'rejects invalid whatsapp_code formats' do
      product = Product.new(
        product_sku: "SKU-UNIQ-#{SecureRandom.hex(4)}",
        product_name: 'Name E',
        brand: 'BrandQ',
        category: 'diecast',
        whatsapp_code: 'ABC1',
        selling_price: 100,
        minimum_price: 50,
        maximum_discount: 0
      )

      expect(product).not_to be_valid
      expect(product.errors[:whatsapp_code]).to include('must use format AA00')
    end

    it 'allows legacy whatsapp_code values when unchanged' do
      product = create(:product, whatsapp_code: 'AC10')
      product.update_column(:whatsapp_code, 'WGT001')
      product.product_name = 'Nombre actualizado'

      expect(product).to be_valid
    end
  end

  describe '#available_by_condition' do
    let(:product) { create(:product, skip_seed_inventory: true, selling_price: 100) }
    let(:location) { create(:inventory_location, :warehouse) }

    context 'when product has no inventory' do
      it 'returns an empty array' do
        expect(product.available_by_condition).to eq([])
      end
    end

    context 'when product has only brand_new inventory' do
      before do
        create_list(:inventory, 3, product: product, status: :available, item_condition: :brand_new, inventory_location: location)
      end

      it 'returns array with one entry for brand_new' do
        result = product.available_by_condition
        expect(result.size).to eq(1)
        expect(result.first[:condition]).to eq('brand_new')
        expect(result.first[:count]).to eq(3)
        expect(result.first[:price]).to eq(100)
        expect(result.first[:collectible]).to be false
      end
    end

    context 'when product has mixed conditions' do
      before do
        create_list(:inventory, 2, product: product, status: :available, item_condition: :brand_new, inventory_location: location)
        create_list(:inventory, 1, product: product, status: :available, item_condition: :misb, selling_price: 150, inventory_location: location)
        create(:inventory, product: product, status: :available, item_condition: :loose, selling_price: 75, inventory_location: location)
      end

      it 'returns array sorted by condition' do
        result = product.available_by_condition
        expect(result.size).to eq(3)
        expect(result.map { |c| c[:condition] }).to eq(%w[brand_new misb loose])
      end

      it 'marks collectibles correctly' do
        result = product.available_by_condition
        brand_new_entry = result.find { |c| c[:condition] == 'brand_new' }
        misb_entry = result.find { |c| c[:condition] == 'misb' }
        expect(brand_new_entry[:collectible]).to be false
        expect(misb_entry[:collectible]).to be true
      end
    end

    context 'when available pieces have no physical location' do
      before do
        create_list(:inventory, 2, product: product, status: :available, item_condition: :brand_new, inventory_location: nil)
      end

      it 'excludes them (not sellable until located)' do
        expect(product.available_by_condition).to eq([])
      end
    end

    context 'when product has in_transit inventory' do
      before do
        create_list(:inventory, 2, product: product, status: :in_transit, item_condition: :brand_new, inventory_location: nil)
      end

      it 'counts in_transit as sellable brand_new' do
        result = product.available_by_condition
        expect(result.size).to eq(1)
        expect(result.first[:condition]).to eq('brand_new')
        expect(result.first[:count]).to eq(2)
      end
    end

    context 'when available pieces are already reserved (sale_order assigned)' do
      before do
        create(:inventory, product: product, status: :available, item_condition: :brand_new,
                           inventory_location: location, sale_order_id: create(:sale_order).id)
      end

      it 'excludes reserved pieces' do
        expect(product.available_by_condition).to eq([])
      end
    end

    context 'when product has only sold inventory' do
      before do
        create(:inventory, product: product, status: :sold, item_condition: :brand_new)
      end

      it 'returns empty array' do
        expect(product.available_by_condition).to eq([])
      end
    end
  end

  describe '#has_collectibles?' do
    let(:product) { create(:product, skip_seed_inventory: true, selling_price: 100) }
    let(:location) { create(:inventory_location, :warehouse) }

    it 'returns false when no inventory' do
      expect(product.has_collectibles?).to be false
    end

    it 'returns false when only brand_new inventory' do
      create(:inventory, product: product, status: :available, item_condition: :brand_new, inventory_location: location)
      expect(product.has_collectibles?).to be false
    end

    it 'returns true when has misb inventory' do
      create(:inventory, product: product, status: :available, item_condition: :misb, selling_price: 150, inventory_location: location)
      expect(product.has_collectibles?).to be true
    end

    it 'returns true when has loose inventory' do
      create(:inventory, product: product, status: :available, item_condition: :loose, selling_price: 80, inventory_location: location)
      expect(product.has_collectibles?).to be true
    end
  end

  describe '#total_available' do
    let(:product) { create(:product, skip_seed_inventory: true, selling_price: 100) }
    let(:location) { create(:inventory_location, :warehouse) }

    it 'returns 0 when no inventory' do
      expect(product.total_available).to eq(0)
    end

    it 'sums all sellable conditions (located available + in_transit)' do
      create_list(:inventory, 2, product: product, status: :available, item_condition: :brand_new, inventory_location: location)
      create(:inventory, product: product, status: :available, item_condition: :misb, selling_price: 150, inventory_location: location)
      create(:inventory, product: product, status: :sold, item_condition: :brand_new)
      expect(product.total_available).to eq(3)
    end

    it 'excludes available pieces without a physical location' do
      create(:inventory, product: product, status: :available, item_condition: :brand_new, inventory_location: nil)
      expect(product.total_available).to eq(0)
    end
  end

  describe '#auto_pause_if_unpublishable!' do
    let(:product) do
      create(:product, skip_seed_inventory: true, status: :active,
                       preorder_available: false, backorder_allowed: false)
    end
    let(:location) { create(:inventory_location, :warehouse) }

    it 'pausa (inactive + auto_paused) cuando no hay stock publicable' do
      product.auto_pause_if_unpublishable!
      product.reload
      expect(product.status).to eq('inactive')
      expect(product.auto_paused).to be(true)
      expect(product.auto_paused_at).to be_present
    end

    it 'NO pausa si hay :available con ubicación confirmada' do
      create(:inventory, product: product, status: :available,
                         inventory_location: location, item_condition: :brand_new)
      product.auto_pause_if_unpublishable!
      expect(product.reload.status).to eq('active')
    end

    it 'SÍ pausa si la pieza :available no tiene ubicación' do
      create(:inventory, product: product, status: :available,
                         inventory_location: nil, item_condition: :brand_new)
      product.auto_pause_if_unpublishable!
      expect(product.reload.status).to eq('inactive')
    end

    it 'NO pausa si hay inventario en tránsito (no requiere ubicación)' do
      create(:inventory, product: product, status: :in_transit, item_condition: :brand_new)
      product.auto_pause_if_unpublishable!
      expect(product.reload.status).to eq('active')
    end

    it 'NO pausa si el producto permite preorder' do
      product.update!(preorder_available: true)
      product.auto_pause_if_unpublishable!
      expect(product.reload.status).to eq('active')
    end

    it 'NO pausa si el producto permite backorder' do
      product.update!(backorder_allowed: true)
      product.auto_pause_if_unpublishable!
      expect(product.reload.status).to eq('active')
    end

    it 'no toca productos en draft' do
      product.update!(status: :draft)
      product.auto_pause_if_unpublishable!
      expect(product.reload.status).to eq('draft')
    end

    it 'se dispara cuando una pieza con ubicación pasa a :sold y deja al producto sin stock' do
      inv = create(:inventory, product: product, status: :available,
                               inventory_location: location, item_condition: :brand_new)
      expect(product.reload.status).to eq('active')
      inv.update!(status: :sold)
      expect(product.reload.status).to eq('inactive')
      expect(product.reload.auto_paused).to be(true)
    end

    it 'se dispara al quitar la ubicación de la única pieza :available' do
      inv = create(:inventory, product: product, status: :available,
                               inventory_location: location, item_condition: :brand_new)
      expect(product.reload.status).to eq('active')
      inv.update!(inventory_location: nil)
      expect(product.reload.status).to eq('inactive')
    end
  end

  describe '#primary_product_image' do
    let(:product) { create(:product, skip_seed_inventory: true) }

    it 'returns the selected primary attachment first' do
      second_attachment = product.product_images.attachments.second

      product.set_primary_product_image!(second_attachment.id)

      expect(product.reload.primary_product_image.id).to eq(second_attachment.id)
      expect(product.ordered_product_images.first.id).to eq(second_attachment.id)
    end

    it 'falls back to the first available image when the stored primary attachment is missing' do
      product.update_column(:primary_product_image_attachment_id, 999_999)

      expect(product.reload.primary_product_image).to be_present
      expect(product.primary_product_image.id).to eq(product.product_images.attachments.order(:created_at).first.id)
    end
  end
end