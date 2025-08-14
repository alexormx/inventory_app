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


# 10 productos draft
50.times do |i|
	Product.create!(
		product_name: "Draft - #{Faker::Commerce.product_name}",
		product_sku: "SKU_DRAFT_#{1000 + i}",
		whatsapp_code: "WSP_DRAFT_#{1000 + i}",
		barcode: Faker::Barcode.ean,
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
end

# 10 productos activos
50.times do |i|
	Product.create!(
		product_name: "Active - #{Faker::Commerce.product_name}",
		product_sku: "SKU_ACTIVE_#{1000 + i}",
		whatsapp_code: "WSP_ACTIVE_#{1000 + i}",
		barcode: Faker::Barcode.ean,
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
end

# 10 productos inactivos
50.times do |i|
	Product.create!(
		product_name: "Inactive - #{Faker::Commerce.product_name}",
		product_sku: "SKU_INACTIVE_#{1000 + i}",
		whatsapp_code: "WSP_INACTIVE_#{1000 + i}",
		barcode: Faker::Barcode.ean,
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
end
