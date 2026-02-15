# frozen_string_literal: true

class Cart
  FREE_SHIPPING_THRESHOLD = 1500
  SHIPPING_FLAT = 99

  # Límites por tipo de condición
  MAX_NEW_ITEMS_PER_PRODUCT = 3
  MAX_COLLECTIBLE_ITEMS_PER_PIECE = 1

  def initialize(session)
    @session = session
    @session[:cart] ||= {}
    migrate_legacy_cart_format!
  end

  # Agrega un producto con condición específica
  # condition: 'brand_new', 'misb', 'moc', etc.
  def add_product(product_id, quantity = 1, condition: 'brand_new')
    condition = condition.to_s
    pid = product_id.to_s
    @session[:cart][pid] ||= {}
    @session[:cart][pid][condition] ||= 0
    @session[:cart][pid][condition] += quantity.to_i
    invalidate_cache!
  end

  # Actualiza cantidad para producto + condición
  def update(product_id, quantity, condition: 'brand_new')
    condition = condition.to_s
    pid = product_id.to_s
    if quantity.to_i <= 0
      remove(product_id, condition: condition)
    else
      @session[:cart][pid] ||= {}
      @session[:cart][pid][condition] = quantity.to_i
    end
    invalidate_cache!
  end

  # Elimina una condición específica de un producto
  def remove(product_id, condition: nil)
    pid = product_id.to_s
    if condition.present?
      @session[:cart][pid]&.delete(condition.to_s)
      # Limpiar producto si ya no tiene condiciones
      @session[:cart].delete(pid) if @session[:cart][pid] && @session[:cart][pid].empty?
    else
      # Eliminar todas las condiciones del producto
      @session[:cart].delete(pid)
    end
    invalidate_cache!
  end

  # Invalida el cache de items para forzar recarga
  def invalidate_cache!
    @items = nil
  end

  # Obtener cantidad para producto + condición
  def quantity_for(product_id, condition: 'brand_new')
    @session[:cart].dig(product_id.to_s, condition.to_s) || 0
  end

  # Cantidad total de un producto (todas las condiciones)
  def total_quantity_for(product_id)
    @session[:cart][product_id.to_s]&.values&.sum || 0
  end

  # Items del carrito: [{ product:, condition:, quantity:, price: }, ...]
  def items
    load_items
  end

  # Carga los items - se puede llamar múltiples veces sin problema de cache stale
  def load_items
    @load_items ||= build_items
  end

  # Fuerza recarga de items (útil después de modificaciones)
  def reload_items!
    @items = nil
    load_items
  end

  # Total del carrito (suma de line_total de cada item)
  def total
    load_items.sum { |item| item[:line_total] }
  end

  def item_count
    load_items.sum { |item| item[:quantity] }
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

  # Shipping cost - solo se calcula si hay items en el carrito
  # En el carrito mostramos el estimado; el costo real depende del método de envío en checkout
  def shipping_cost
    return 0 if empty?
    return 0 if total >= FREE_SHIPPING_THRESHOLD

    SHIPPING_FLAT
  end

  def grand_total
    subtotal + tax_amount + shipping_cost
  end

  def tax_enabled?
    [true, 'true'].include?(SiteSetting.get('tax_enabled', 'true'))
  end

  def tax_rate_percent
    SiteSetting.get('tax_rate_percent', 16).to_i
  end

  def tax_rate
    tax_rate_percent.to_f / 100.0
  end

  def empty?
    @session[:cart].empty? || @session[:cart].values.all?(&:empty?)
  end

  # Validaciones de límite
  def can_add?(product_id, condition: 'brand_new', quantity: 1)
    current = quantity_for(product_id, condition: condition)
    new_total = current + quantity.to_i

    new_total <= if condition.to_s == 'brand_new'
                   MAX_NEW_ITEMS_PER_PRODUCT
                 else
                   # Coleccionables: máximo 1 por condición
                   MAX_COLLECTIBLE_ITEMS_PER_PIECE
                 end
  end

  def max_allowed(condition)
    condition.to_s == 'brand_new' ? MAX_NEW_ITEMS_PER_PRODUCT : MAX_COLLECTIBLE_ITEMS_PER_PIECE
  end

  private

  # Migrar formato legacy {product_id => qty} a {product_id => {condition => qty}}
  def migrate_legacy_cart_format!
    return if @session[:cart].empty?

    needs_migration = @session[:cart].any? { |_k, v| !v.is_a?(Hash) }
    return unless needs_migration

    migrated = {}
    @session[:cart].each do |product_id, value|
      migrated[product_id] = if value.is_a?(Hash)
                               value
                             else
                               # Legacy: valor numérico -> migrar a brand_new
                               { 'brand_new' => value.to_i }
                             end
    end
    @session[:cart] = migrated
  end

  def build_items
    result = []
    @session[:cart].each do |product_id, conditions|
      product = Product.find_by(id: product_id)
      next unless product

      conditions.each do |condition, quantity|
        next if quantity.to_i <= 0

        price = price_for_condition(product, condition)
        result << {
          product: product,
          condition: condition,
          quantity: quantity.to_i,
          price: price,
          collectible: condition != 'brand_new',
          label: condition_label(condition),
          line_total: price * quantity.to_i
        }
      end
    end
    result
  end

  def price_for_condition(product, condition)
    if condition.to_s == 'brand_new'
      product.selling_price
    else
      # Obtener precio promedio de inventario disponible con esa condición
      avg_price = product.inventories.where(status: :available, item_condition: condition)
                         .average(:selling_price)
      avg_price&.to_f || product.selling_price
    end
  end

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
