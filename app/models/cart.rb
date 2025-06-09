class Cart
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
    @session[:cart].map do |product_id, quantity|
      product = Product.find_by(id: product_id)
      [product, quantity.to_i] if product
    end.compact
  end

  def total
    items.sum { |product, quantity| product.selling_price * quantity }
  end

  def empty?
    @session[:cart].empty?
  end
end