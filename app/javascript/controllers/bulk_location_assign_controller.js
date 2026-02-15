import { Controller } from "@hotwired/stimulus"

// Controlador para asignación masiva de ubicación a inventario (v2 - con carrito)
// Flujo: 1) Seleccionar ubicación  2) Buscar y agregar piezas al carrito  3) Asignar todo
export default class extends Controller {
  static targets = [
    "productGroup",        // Cada fila <tr> de producto
    "quantityInput",       // Input numérico de cantidad a agregar
    "counter",             // Contador total de piezas en carrito
    "submitBtn",           // Botón de asignar
    "locationInput",       // Campo hidden de ubicación seleccionada
    "locationIndicator",   // Indicador visual de ubicación seleccionada
    "locationContents",    // Panel de piezas existentes en la ubicación
    "locationContentsBody",// Contenido del panel de piezas existentes
    "locationContentsIcon",// Icono de toggle del panel
    "cartList",            // Lista de items en el carrito
    "cartBadge",           // Badge del conteo del carrito
    "cartEmpty",           // Estado vacío del carrito
    "clearCartBtn"         // Botón vaciar carrito
  ]

  static values = {
    locationContentsUrl: { type: String, default: "" }
  }

  connect() {
    // Carrito en memoria: Map<productId, { name, sku, quantity, maxAvailable }>
    this._cart = new Map()
    this._selectedLocationId = null
    this._selectedLocationName = ""
    this._updateUI()
  }

  // ═══ UBICACIÓN ═══

  // Cuando se selecciona una ubicación desde location-suggest
  locationSelected() {
    const locId = this.locationInputTarget.value.trim()
    if (!locId) {
      this._selectedLocationId = null
      this._selectedLocationName = ""
      this._hideLocationContents()
      this._updateLocationIndicator()
      this._updateUI()
      return
    }

    this._selectedLocationId = locId
    // Obtener nombre del hint del location-suggest
    const hintEl = this.element.querySelector('[data-location-suggest-target="hint"]')
    if (hintEl) {
      this._selectedLocationName = hintEl.textContent.trim()
    }

    this._updateLocationIndicator()
    this._loadLocationContents(locId)
    this._updateUI()
  }

  _updateLocationIndicator() {
    if (!this.hasLocationIndicatorTarget) return

    if (this._selectedLocationId) {
      this.locationIndicatorTarget.innerHTML = `
        <div class="text-center">
          <i class="fas fa-check-circle text-success fs-5"></i>
          <div class="small fw-bold text-success mt-1">Ubicación lista</div>
        </div>`
    } else {
      this.locationIndicatorTarget.innerHTML = `
        <span><i class="fas fa-arrow-left me-1"></i> Selecciona una ubicación para comenzar</span>`
    }
  }

  _loadLocationContents(locationId) {
    if (!this.hasLocationContentsTarget) return

    const url = this.locationContentsUrlValue.replace('__ID__', locationId)
    this.locationContentsTarget.style.display = ''
    this.locationContentsBodyTarget.innerHTML = `
      <div class="text-center py-3 text-muted">
        <i class="fas fa-spinner fa-spin"></i> Cargando piezas...
      </div>`

    fetch(url, { headers: { 'Accept': 'text/html', 'X-Requested-With': 'XMLHttpRequest' } })
      .then(r => r.text())
      .then(html => { this.locationContentsBodyTarget.innerHTML = html })
      .catch(() => {
        this.locationContentsBodyTarget.innerHTML = `
          <div class="text-center py-3 text-danger">
            <i class="fas fa-exclamation-triangle"></i> Error al cargar
          </div>`
      })
  }

  _hideLocationContents() {
    if (this.hasLocationContentsTarget) {
      this.locationContentsTarget.style.display = 'none'
    }
  }

  toggleLocationContents() {
    if (!this.hasLocationContentsBodyTarget) return
    const body = this.locationContentsBodyTarget
    const icon = this.hasLocationContentsIconTarget ? this.locationContentsIconTarget : null

    if (body.style.display === 'none') {
      body.style.display = ''
      if (icon) icon.classList.replace('fa-chevron-down', 'fa-chevron-up')
    } else {
      body.style.display = 'none'
      if (icon) icon.classList.replace('fa-chevron-up', 'fa-chevron-down')
    }
  }

  // ═══ CARRITO ═══

  // Agregar producto al carrito desde la tabla
  addToCart(event) {
    event.preventDefault()
    if (!this._selectedLocationId) {
      this._flashWarning("Primero selecciona una ubicación destino")
      return
    }

    const row = event.currentTarget.closest('[data-bulk-location-assign-target="productGroup"]')
    if (!row) return

    const productId = row.dataset.productId
    const productName = row.dataset.productName
    const productSku = row.dataset.productSku
    const maxAvailable = parseInt(row.dataset.unlocatedCount, 10) || 0
    const input = row.querySelector('[data-bulk-location-assign-target="quantityInput"]')
    let quantity = parseInt(input?.value, 10) || 0

    if (quantity <= 0) {
      this._flashWarning("La cantidad debe ser mayor a 0")
      return
    }

    // Si ya existe en el carrito, sumar (sin exceder max)
    if (this._cart.has(productId)) {
      const existing = this._cart.get(productId)
      const newQty = Math.min(existing.quantity + quantity, maxAvailable)
      existing.quantity = newQty
    } else {
      quantity = Math.min(quantity, maxAvailable)
      this._cart.set(productId, { name: productName, sku: productSku, quantity, maxAvailable })
    }

    // Feedback visual: flash verde en la fila
    row.style.transition = 'background-color 0.3s'
    row.style.backgroundColor = '#d1e7dd'
    setTimeout(() => { row.style.backgroundColor = '' }, 600)

    this._renderCart()
    this._updateUI()
  }

  // Eliminar item del carrito
  removeFromCart(event) {
    event.preventDefault()
    const productId = event.currentTarget.dataset.productId
    this._cart.delete(productId)
    this._renderCart()
    this._updateUI()
  }

  // Vaciar carrito completo
  clearCart(event) {
    if (event) event.preventDefault()
    this._cart.clear()
    this._renderCart()
    this._updateUI()
  }

  _renderCart() {
    if (!this.hasCartListTarget) return

    if (this._cart.size === 0) {
      this.cartListTarget.innerHTML = `
        <div class="text-center text-muted py-4" id="cart-empty-state">
          <i class="fas fa-cart-plus fa-2x mb-2 d-block"></i>
          <small>Agrega piezas desde la tabla de la izquierda</small>
        </div>`
      return
    }

    let html = '<div class="list-group list-group-flush">'
    for (const [productId, item] of this._cart) {
      html += `
        <div class="list-group-item py-2 px-3 d-flex justify-content-between align-items-center"
             id="cart-item-${productId}">
          <div class="me-2" style="min-width: 0; flex: 1;">
            <div class="fw-bold small text-truncate">${this._escapeHtml(item.name)}</div>
            <code class="small text-muted">${this._escapeHtml(item.sku)}</code>
          </div>
          <div class="d-flex align-items-center gap-2 flex-shrink-0">
            <span class="badge bg-primary">${item.quantity}</span>
            <button type="button" class="btn btn-sm btn-outline-danger py-0 px-1"
                    data-action="click->bulk-location-assign#removeFromCart"
                    data-product-id="${productId}"
                    title="Quitar del carrito">
              <i class="fas fa-times"></i>
            </button>
          </div>
        </div>`
    }
    html += '</div>'
    this.cartListTarget.innerHTML = html
  }

  _getCartTotal() {
    let total = 0
    for (const item of this._cart.values()) {
      total += item.quantity
    }
    return total
  }

  // ═══ SUBMIT ═══

  submitAssignment(event) {
    event.preventDefault()
    if (!this._selectedLocationId || this._cart.size === 0) return

    const total = this._getCartTotal()
    if (!confirm(`¿Asignar ${total} pieza${total === 1 ? '' : 's'} a la ubicación seleccionada?`)) return

    // Construir assignments
    const assignments = {}
    for (const [productId, item] of this._cart) {
      assignments[productId] = item.quantity
    }

    // Deshabilitar botón
    this.submitBtnTarget.disabled = true
    this.submitBtnTarget.innerHTML = '<i class="fas fa-spinner fa-spin me-1"></i> Asignando...'

    // Obtener CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    // POST via fetch para recibir turbo stream response
    const formData = new FormData()
    formData.append('inventory_location_id', this._selectedLocationId)
    for (const [productId, qty] of Object.entries(assignments)) {
      formData.append(`assignments[${productId}]`, qty)
    }

    fetch('/admin/inventory/bulk_assign_location', {
      method: 'POST',
      headers: {
        'X-CSRF-Token': csrfToken,
        'Accept': 'text/vnd.turbo-stream.html, text/html'
      },
      body: formData
    })
      .then(response => {
        if (response.ok) {
          return response.text()
        }
        throw new Error('Error en la asignación')
      })
      .then(html => {
        // Procesar turbo streams si los hay
        if (html.includes('turbo-stream')) {
          Turbo.renderStreamMessage(html)
        }

        // Limpiar carrito
        this._cart.clear()
        this._renderCart()
        this._updateUI()

        // Recargar piezas de la ubicación
        if (this._selectedLocationId) {
          this._loadLocationContents(this._selectedLocationId)
        }
      })
      .catch(error => {
        console.error('Bulk assign error:', error)
        alert('Error al asignar. Intenta de nuevo.')
      })
      .finally(() => {
        this.submitBtnTarget.disabled = false
        this.submitBtnTarget.innerHTML = '<i class="fas fa-check me-1"></i> Asignar Todo a Ubicación'
        this._updateUI()
      })
  }

  // ═══ EXPAND / COLLAPSE ═══

  toggleGroup(event) {
    event.preventDefault()
    const button = event.currentTarget
    const group = button.closest('[data-bulk-location-assign-target="productGroup"]')
    const detailRow = group.nextElementSibling
    const icon = button.querySelector('.toggle-icon')

    if (!detailRow || !detailRow.classList.contains('detail-row')) return

    const isHidden = detailRow.style.display === 'none'

    if (isHidden) {
      detailRow.style.display = ''
      if (icon) icon.classList.replace('fa-chevron-right', 'fa-chevron-down')

      const detailContent = detailRow.querySelector('.detail-content')
      const url = button.dataset.url

      if (url && detailContent && !detailContent.dataset.loaded) {
        fetch(url, { headers: { 'Accept': 'text/html', 'X-Requested-With': 'XMLHttpRequest' } })
          .then(r => r.text())
          .then(html => {
            detailContent.innerHTML = html
            detailContent.dataset.loaded = 'true'
          })
          .catch(() => {
            detailContent.innerHTML = '<p class="text-danger p-3"><i class="fas fa-exclamation-triangle"></i> Error al cargar</p>'
          })
      }
    } else {
      detailRow.style.display = 'none'
      if (icon) icon.classList.replace('fa-chevron-down', 'fa-chevron-right')
    }
  }

  expandAll(event) {
    event.preventDefault()
    this.productGroupTargets.forEach(group => {
      const button = group.querySelector('.toggle-btn')
      const detailRow = group.nextElementSibling
      const icon = group.querySelector('.toggle-icon')

      if (detailRow && detailRow.classList.contains('detail-row')) {
        detailRow.style.display = ''
        if (icon) icon.classList.replace('fa-chevron-right', 'fa-chevron-down')

        const detailContent = detailRow.querySelector('.detail-content')
        const url = button?.dataset.url
        if (url && detailContent && !detailContent.dataset.loaded) {
          fetch(url, { headers: { 'Accept': 'text/html', 'X-Requested-With': 'XMLHttpRequest' } })
            .then(r => r.text())
            .then(html => { detailContent.innerHTML = html; detailContent.dataset.loaded = 'true' })
            .catch(() => { detailContent.innerHTML = '<p class="text-danger p-3">Error</p>' })
        }
      }
    })
  }

  collapseAll(event) {
    event.preventDefault()
    this.productGroupTargets.forEach(group => {
      const detailRow = group.nextElementSibling
      const icon = group.querySelector('.toggle-icon')
      if (detailRow && detailRow.classList.contains('detail-row')) {
        detailRow.style.display = 'none'
        if (icon) icon.classList.replace('fa-chevron-down', 'fa-chevron-right')
      }
    })
  }

  // ═══ HELPERS ═══

  _updateUI() {
    const total = this._getCartTotal()
    const hasLocation = !!this._selectedLocationId
    const hasItems = total > 0

    // Counter
    if (this.hasCounterTarget) {
      this.counterTarget.textContent = total
      this.counterTarget.classList.toggle('text-success', hasItems)
      this.counterTarget.classList.toggle('text-muted', !hasItems)
    }

    // Cart badge
    if (this.hasCartBadgeTarget) {
      this.cartBadgeTarget.textContent = this._cart.size
    }

    // Submit button
    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = !(hasLocation && hasItems)
    }

    // Clear cart button
    if (this.hasClearCartBtnTarget) {
      this.clearCartBtnTarget.style.display = hasItems ? '' : 'none'
    }
  }

  _flashWarning(message) {
    const flashDiv = document.getElementById('flash-messages')
    if (!flashDiv) { alert(message); return }

    flashDiv.innerHTML = `
      <div class="alert alert-warning alert-dismissible fade show" role="alert">
        <i class="fas fa-exclamation-triangle"></i> ${this._escapeHtml(message)}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
      </div>`

    setTimeout(() => {
      const alert = flashDiv.querySelector('.alert')
      if (alert) alert.remove()
    }, 3000)
  }

  _escapeHtml(str) {
    if (!str) return ''
    const div = document.createElement('div')
    div.textContent = str
    return div.innerHTML
  }
}
