# frozen_string_literal: true

# Helper para crear carritos de prueba con el nuevo formato
module CartTestHelper
  # Crea un array de items de carrito en el nuevo formato
  # Uso: build_cart_items(product, 2) o build_cart_items(product, 1, condition: 'misb')
  def build_cart_items(product, qty, condition: 'brand_new')
    price = if condition == 'brand_new'
              product.selling_price
            else
              product.inventories.where(status: :available, item_condition: condition)
                     .average(:selling_price)&.to_f || product.selling_price
            end
    [{
      product: product,
      condition: condition.to_s,
      quantity: qty,
      price: price,
      collectible: condition.to_s != 'brand_new',
      label: condition_label(condition),
      line_total: price * qty
    }]
  end

  # Crea un carrito mock con items en el nuevo formato
  def mock_cart_with_items(items_array)
    instance_double('Cart',
      empty?: items_array.empty?,
      items: items_array,
      total: items_array.sum { |item| item[:line_total] }
    )
  end

  # Shortcut para crear un carrito simple con un producto
  def mock_simple_cart(product, qty, condition: 'brand_new')
    mock_cart_with_items(build_cart_items(product, qty, condition: condition))
  end

  private

  def condition_label(condition)
    case condition.to_s
    when 'brand_new' then 'Nuevo'
    when 'misb' then 'MISB'
    when 'moc' then 'MOC'
    when 'mib' then 'MIB'
    when 'mint' then 'Mint'
    when 'loose' then 'Loose'
    when 'good' then 'Good'
    when 'fair' then 'Fair'
    else condition.to_s.titleize
    end
  end
end

RSpec.configure do |config|
  config.include CartTestHelper
end
