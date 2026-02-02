import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["existingSection", "newSection", "searchInput", "searchResults", "existingProductId", "productPreview", "productName"]

  connect() {
    this.debounceTimer = null
  }

  toggleProductMode(event) {
    const useExisting = event.target.value === '1'

    if (useExisting) {
      this.existingSectionTarget.classList.remove('d-none')
      this.newSectionTarget.classList.add('d-none')
      // Limpiar campos de nuevo producto
      this.newSectionTarget.querySelectorAll('input, textarea').forEach(el => {
        el.removeAttribute('required')
      })
    } else {
      this.existingSectionTarget.classList.add('d-none')
      this.newSectionTarget.classList.remove('d-none')
      // Restaurar required
      this.newSectionTarget.querySelector('[name="product[product_name]"]')?.setAttribute('required', 'required')
      // Limpiar selección
      this.existingProductIdTarget.value = ''
      this.productPreviewTarget.classList.add('d-none')
    }
  }

  searchProducts(event) {
    const query = event.target.value.trim()

    clearTimeout(this.debounceTimer)

    if (query.length < 2) {
      this.searchResultsTarget.innerHTML = ''
      return
    }

    this.debounceTimer = setTimeout(() => {
      this.performSearch(query)
    }, 300)
  }

  async performSearch(query) {
    try {
      const response = await fetch(`/admin/collectibles/search_products?query=${encodeURIComponent(query)}`, {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (!response.ok) throw new Error('Search failed')

      const products = await response.json()
      this.renderSearchResults(products)
    } catch (error) {
      console.error('Search error:', error)
      this.searchResultsTarget.innerHTML = ''
    }
  }

  renderSearchResults(products) {
    if (products.length === 0) {
      this.searchResultsTarget.innerHTML = '<div class="list-group-item text-muted">No se encontraron productos</div>'
      return
    }

    this.searchResultsTarget.innerHTML = products.map(p => `
      <button type="button" class="list-group-item list-group-item-action"
              data-action="click->collectible-quick-add#selectProduct"
              data-product-id="${p.id}"
              data-product-name="${p.product_name}"
              data-product-sku="${p.product_sku}">
        <div class="d-flex justify-content-between align-items-center">
          <div>
            <strong>${p.product_name}</strong>
            <br><small class="text-muted">SKU: ${p.product_sku} | ${p.category || 'Sin categoría'} | ${p.brand || 'Sin marca'}</small>
          </div>
          ${p.base_price ? `<span class="badge bg-secondary">$${parseFloat(p.base_price).toFixed(2)}</span>` : ''}
        </div>
      </button>
    `).join('')
  }

  selectProduct(event) {
    const button = event.currentTarget
    const productId = button.dataset.productId
    const productName = button.dataset.productName
    const productSku = button.dataset.productSku

    this.existingProductIdTarget.value = productId
    this.productNameTarget.textContent = `${productName} (${productSku})`
    this.productPreviewTarget.classList.remove('d-none')
    this.searchResultsTarget.innerHTML = ''
    this.searchInputTarget.value = ''
  }
}
