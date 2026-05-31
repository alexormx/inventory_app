# frozen_string_literal: true

# Habilita la búsqueda tolerante a errores de tecleo (fuzzy) en el catálogo
# público. pg_trgm aporta el operador `%` (similitud de trigramas) y acelera
# ILIKE '%texto%' mediante índices GIN gin_trgm_ops sobre los campos de
# búsqueda. Ver Product.search_catalog / Product.search_relevance_order.
class AddTrigramSearchToProducts < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    enable_extension 'pg_trgm' unless extension_enabled?('pg_trgm')

    add_index :products, :product_name, using: :gin, opclass: :gin_trgm_ops,
              name: 'index_products_on_product_name_trgm',
              algorithm: :concurrently, if_not_exists: true
    add_index :products, :brand, using: :gin, opclass: :gin_trgm_ops,
              name: 'index_products_on_brand_trgm',
              algorithm: :concurrently, if_not_exists: true
    add_index :products, :category, using: :gin, opclass: :gin_trgm_ops,
              name: 'index_products_on_category_trgm',
              algorithm: :concurrently, if_not_exists: true
    add_index :products, :series, using: :gin, opclass: :gin_trgm_ops,
              name: 'index_products_on_series_trgm',
              algorithm: :concurrently, if_not_exists: true

    # Código de WhatsApp: la búsqueda lo consulta por igualdad exacta y la
    # validación de unicidad hace `exists?` en cada guardado.
    add_index :products, :whatsapp_code,
              name: 'index_products_on_whatsapp_code',
              algorithm: :concurrently, if_not_exists: true
  end

  def down
    remove_index :products, name: 'index_products_on_product_name_trgm', if_exists: true
    remove_index :products, name: 'index_products_on_brand_trgm', if_exists: true
    remove_index :products, name: 'index_products_on_category_trgm', if_exists: true
    remove_index :products, name: 'index_products_on_series_trgm', if_exists: true
    remove_index :products, name: 'index_products_on_whatsapp_code', if_exists: true
    # No removemos la extensión pg_trgm: podría usarse en otros índices/consultas.
  end
end
