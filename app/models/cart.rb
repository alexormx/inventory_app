class Cart
  FREE_SHIPPING_THRESHOLD = 1500
  SHIPPING_FLAT = 99
  def initialize(session)
    @session = session
    @session[:cart] ||= {}
  end

  def add_product(product_id, quantity = 1)
    @session[:cart][product_id.to_s] ||= 0
    @session[:cart][product_id.to_s] += quantity.to_i
  end

  def update(product_id, quantity)
    if quantity.to_i <= 0
      remove(product_id)
    else
      @session[:cart][product_id.to_s] = quantity.to_i
    end
  end

  def remove(product_id)
    @session[:cart].delete(product_id.to_s)
  end

  def items
    @_items ||= @session[:cart].map do |product_id, quantity|
      product = Product.find_by(id: product_id)
      [product, quantity.to_i] if product
    end.compact
  end

  def total
    items.sum { |product, quantity| product.selling_price * quantity }
  end

  def item_count
    items.sum { |_, quantity| quantity.to_i }
  end

  # Subtotal alias for clarity in views
  def subtotal
    total
  end

  def tax_amount
  return 0 unless tax_enabled?
  return 0 if subtotal.zero?
  (subtotal * tax_rate).round(2)
  end

  def shipping_cost
    return 0 if subtotal.zero? || subtotal >= FREE_SHIPPING_THRESHOLD
    SHIPPING_FLAT
  end

  def grand_total
    subtotal + tax_amount + shipping_cost
  end

  def tax_enabled?
    SiteSetting.get('tax_enabled', 'true') == true || SiteSetting.get('tax_enabled', 'true') == 'true'
  end

  def tax_rate_percent
    SiteSetting.get('tax_rate_percent', 16).to_i
  end

  def tax_rate
    tax_rate_percent.to_f / 100.0
  end

  def empty?
    @session[:cart].empty?
  end
end