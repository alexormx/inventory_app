# Sample SEPOMEX postal codes (minimal) for dev/test
if ENV['SEED_POSTAL_CODES']
	sample = [
		{ cp: '36500', state: 'guanajuato', municipality: 'irapuato', settlement: 'centro', settlement_type: 'colonia' },
		{ cp: '36500', state: 'guanajuato', municipality: 'irapuato', settlement: 'modulo i', settlement_type: 'colonia' },
		{ cp: '01000', state: 'ciudad de méxico', municipality: 'álvaro obregón', settlement: 'san ángel', settlement_type: 'colonia' }
	]
	sample.each do |row|
		PostalCode.find_or_create_by!(row)
	end
	puts "Seeded postal codes"
end
# Site settings initial values (idempotent)
SiteSetting.set('language_switcher_enabled', false) unless SiteSetting.get('language_switcher_enabled') == false
SiteSetting.set('dark_mode_enabled', false) unless SiteSetting.get('dark_mode_enabled') == false
# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

require 'faker'

def seed_log(msg)
	puts "[SEED] #{msg}"
end

def ten_digit_phone
	Array.new(10) { rand(0..9) }.join
end
# --- Users seed: admins, suppliers, customers ---

seed_log "Ensuring admin user..."
# Ensure at least one admin with known credentials
admin = User.find_or_initialize_by(email: "admin@example.com")
admin.assign_attributes(
	name: "Admin Seed",
	role: "admin",
	password: "password123",
	phone: ten_digit_phone,
	address: Faker::Address.full_address
)
admin.skip_confirmation! if admin.respond_to?(:skip_confirmation!)
admin.confirmed_at ||= Time.current
admin.save! if admin.changed?
seed_log "Admin ready: #{admin.email} (id=#{admin.id})"

seed_log "Creating suppliers..."
5.times do
	begin
		User.find_or_create_by!(
			email: Faker::Internet.unique.email,
			role: "supplier"
		) do |u|
			u.name = Faker::Company.name
			u.password = Devise.friendly_token.first(12)
			u.phone = ten_digit_phone
			u.address = Faker::Address.full_address
		u.skip_confirmation! if u.respond_to?(:skip_confirmation!)
		u.confirmed_at ||= Time.current
		end
	rescue ActiveRecord::RecordInvalid => e
		seed_log "Supplier error: #{e.record.errors.full_messages.join(', ')}"
	end
end

# Customers (algunos offline sin email)
seed_log "Creating customers..."
10.times do
	attrs = {
		name: Faker::Name.name,
		role: "customer",
		phone: ten_digit_phone,
		address: Faker::Address.full_address,
		discount_rate: rand(0.0..10.0).round(2),
		created_offline: [true, false].sample
	}

		if attrs[:created_offline]
		# cliente offline sin email/contraseña
		u = User.new(attrs)
		u.password = Devise.friendly_token.first(12)
			u.skip_confirmation! if u.respond_to?(:skip_confirmation!)
			u.confirmed_at ||= Time.current
				begin
					u.email = "offline-#{SecureRandom.hex(6)}@seed.local"
					u.save!
			rescue ActiveRecord::RecordInvalid => e
				seed_log "Customer (offline) error: #{e.record.errors.full_messages.join(', ')}"
			end
	else
			begin
				User.find_or_create_by!(email: Faker::Internet.unique.email) do |u|
					u.assign_attributes(attrs)
					u.password = Devise.friendly_token.first(12)
				u.skip_confirmation! if u.respond_to?(:skip_confirmation!)
				u.confirmed_at ||= Time.current
				end
			rescue ActiveRecord::RecordInvalid => e
				seed_log "Customer error: #{e.record.errors.full_messages.join(', ')}"
			end
	end
end

# Unas órdenes y visitas para estadísticas
seed_log "Creating orders and visits for stats..."
users_for_stats = User.where(role: ["customer", "supplier"]).limit(8)
users_for_stats.each do |u|
	# PurchaseOrders (para suppliers)
	if u.role == "supplier"
		2.times do
					begin
								PurchaseOrder.create!(
				user: u,
				order_date: Faker::Date.between(from: 30.days.ago, to: Date.today),
				expected_delivery_date: Faker::Date.forward(days: 10),
				subtotal: rand(1000..5000),
				total_order_cost: rand(1200..6000),
				shipping_cost: rand(100..500),
				tax_cost: rand(100..500),
				other_cost: rand(0..200),
									status: ["Pending", "In Transit", "Delivered"].sample,
				total_cost: rand(1200..6000),
				total_cost_mxn: rand(1200..6000),
				total_volume: rand(10..100),
				total_weight: rand(10..100)
						)
					rescue ActiveRecord::RecordInvalid => e
						seed_log "PurchaseOrder error for user ##{u.id}: #{e.record.errors.full_messages.join(', ')}"
					end
		end
	end

		# SaleOrders (para customers) con líneas para poblar Sellers/Rentables
		if u.role == "customer"
			2.times do
				begin
					so = SaleOrder.create!(
						user: u,
						order_date: Faker::Date.between(from: 30.days.ago, to: Date.today),
						subtotal: 0,
						tax_rate: 16,
						total_tax: 0,
						total_order_value: 0,
						status: "Pending"
					)

					# Añadir de 1 a 3 líneas aleatorias
					products = Product.active.order("RANDOM()").limit(rand(1..3))
					line_total = 0
					products.each do |p|
						qty = rand(1..3)
						unit_price = (p.selling_price.to_d.nonzero? || rand(100..500).to_d)
						unit_cost  = [unit_price * BigDecimal("0.6"), unit_price - 1].sample # costo aproximado
						line_total += unit_price * qty
						begin
							SaleOrderItem.create!(
								sale_order: so,
								product: p,
								quantity: qty,
								unit_final_price: unit_price,
								unit_cost: unit_cost,
								total_line_cost: unit_cost * qty
							)
						rescue ActiveRecord::RecordInvalid => e
							seed_log "SaleOrderItem error for SO ##{so.id}: #{e.record.errors.full_messages.join(', ')}"
						end
					end
					# Actualizar totales simples
					so.update_columns(
						subtotal: line_total,
						total_tax: (line_total * 0.16).round(2),
						total_order_value: (line_total * 1.16).round(2)
					)
				rescue ActiveRecord::RecordInvalid => e
					seed_log "SaleOrder error for user ##{u.id}: #{e.record.errors.full_messages.join(', ')}"
				end
			end
		end

	# Visitas
		VisitorLog.find_or_create_by!(user_id: u.id, ip_address: Faker::Internet.ip_v4_address, path: "/admin/users") do |v|
		v.user_agent = Faker::Internet.user_agent
		v.last_visited_at = Time.current - rand(1..10).days
		v.visit_count = rand(1..20)
	end
end


def upsert_product!(attrs)
	sku = attrs[:product_sku]
	rec = Product.find_or_initialize_by(product_sku: sku)
	rec.assign_attributes(attrs)
	rec.save!
end

seed_log "Creating draft products..."
50.times do |i|
	begin
		upsert_product!(
			product_name: "Draft - #{Faker::Commerce.product_name}",
			product_sku: "SKU_DRAFT_#{1000 + i}",
			whatsapp_code: "WSP_DRAFT_#{1000 + i}",
			barcode: Faker::Number.number(digits: 12).to_s,
			brand: Faker::Company.name,
			category: Faker::Commerce.department,
			selling_price: Faker::Commerce.price(range: 50..500),
			maximum_discount: rand(5..30),
			minimum_price: Faker::Commerce.price(range: 30..49),
			length_cm: rand(5..50),
			width_cm: rand(5..50),
			height_cm: rand(5..50),
			weight_gr: rand(100..2000),
			description: Faker::Lorem.sentence(word_count: 10),
			status: 'draft'
		)
	rescue ActiveRecord::RecordInvalid => e
		seed_log "Draft product error: #{e.record.errors.full_messages.join(', ')}"
	end
end

seed_log "Creating active products..."
50.times do |i|
	begin
		upsert_product!(
			product_name: "Active - #{Faker::Commerce.product_name}",
			product_sku: "SKU_ACTIVE_#{1000 + i}",
			whatsapp_code: "WSP_ACTIVE_#{1000 + i}",
			barcode: Faker::Number.number(digits: 12).to_s,
			brand: Faker::Company.name,
			category: Faker::Commerce.department,
			selling_price: Faker::Commerce.price(range: 50..500),
			maximum_discount: rand(5..30),
			minimum_price: Faker::Commerce.price(range: 30..49),
			length_cm: rand(5..50),
			width_cm: rand(5..50),
			height_cm: rand(5..50),
			weight_gr: rand(100..2000),
			description: Faker::Lorem.sentence(word_count: 10),
			status: 'active'
		)
	rescue ActiveRecord::RecordInvalid => e
		seed_log "Active product error: #{e.record.errors.full_messages.join(', ')}"
	end
end

seed_log "Creating inactive products..."
50.times do |i|
	begin
		upsert_product!(
			product_name: "Inactive - #{Faker::Commerce.product_name}",
			product_sku: "SKU_INACTIVE_#{1000 + i}",
			whatsapp_code: "WSP_INACTIVE_#{1000 + i}",
			barcode: Faker::Number.number(digits: 12).to_s,
			brand: Faker::Company.name,
			category: Faker::Commerce.department,
			selling_price: Faker::Commerce.price(range: 50..500),
			maximum_discount: rand(5..30),
			minimum_price: Faker::Commerce.price(range: 30..49),
			length_cm: rand(5..50),
			width_cm: rand(5..50),
			height_cm: rand(5..50),
			weight_gr: rand(100..2000),
			description: Faker::Lorem.sentence(word_count: 10),
			status: 'inactive'
		)
	rescue ActiveRecord::RecordInvalid => e
		seed_log "Inactive product error: #{e.record.errors.full_messages.join(', ')}"
	end
end

seed_log "Seeds completed."
