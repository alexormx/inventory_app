# Preview all emails at http://localhost:3000/rails/mailers/order_confirmation_mailer
class OrderConfirmationMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/order_confirmation_mailer/order_confirmation
  def order_confirmation
    # Encontrar o crear una orden de ejemplo para preview
    sale_order = SaleOrder.includes(:sale_order_items, :user, :order_shipping_address).first

    # Si no hay órdenes, crear una de ejemplo
    unless sale_order
      user = User.first || User.create!(
        email: 'ejemplo@pasatiempos.com',
        password: 'password123'
      )
      
      product = Product.first || Product.create!(
        name: 'Producto de Ejemplo',
        sku: 'EJEMPLO-001',
        selling_price: 100.0
      )
      
      sale_order = user.sale_orders.create!(
        order_date: Date.today,
        subtotal: 200.0,
        tax_rate: 0.0,
        total_tax: 0.0,
        shipping_cost: 50.0,
        total_order_value: 250.0,
        notes: 'Esta es una orden de ejemplo para preview',
        status: 'Pending'
      )
      
      sale_order.sale_order_items.create!(
        product: product,
        quantity: 2,
        unit_cost: 100.0,
        total_line_cost: 200.0
      )
      
      address = user.shipping_addresses.first || user.shipping_addresses.create!(
        recipient_name: 'Juan Pérez',
        street_address: 'Calle Principal 123',
        apartment: 'Depto 4B',
        city: 'Ciudad de México',
        state: 'CDMX',
        postal_code: '01000',
        country: 'México',
        phone: '555-1234',
        default: true
      )
      
      OrderShippingAddress.create!(
        sale_order: sale_order,
        recipient_name: address.recipient_name,
        street_address: address.street_address,
        apartment: address.apartment,
        city: address.city,
        state: address.state,
        postal_code: address.postal_code,
        country: address.country,
        phone: address.phone
      )
    end

    OrderConfirmationMailer.order_confirmation(sale_order)
  end
end
