import { Controller } from "@hotwired/stimulus"

// Controlador para transferencia de inventario entre ubicaciones
// Soporta transferencias parciales por cantidad (FIFO)
export default class extends Controller {
  static targets = [
    "sourceSelect",
    "destSelect",
    "sourceItems",
    "destItems",
    "sourceCount",
    "destCount",
    "selectedCount",
    "transferBtn",
    "alerts"
  ]

  connect() {
    this.updateUI()
  }

  // Cargar items de la ubicación origen
  async loadSource() {
    const select = this.sourceSelectTarget
    const option = select.options[select.selectedIndex]
    const url = option?.dataset.url

    if (!url) {
      this.sourceItemsTarget.innerHTML = `
        <div class="p-3 text-center text-muted">
          <i class="fas fa-arrow-up fa-2x mb-2"></i>
          <p>Selecciona una ubicación origen</p>
        </div>
      `
      this.sourceCountTarget.textContent = '0'
      this.updateUI()
      return
    }

    this.sourceItemsTarget.innerHTML = `
      <div class="p-4 text-center">
        <i class="fas fa-spinner fa-spin fa-2x"></i>
        <p class="mt-2">Cargando...</p>
      </div>
    `

    try {
      const response = await fetch(url, {
        headers: { 'Accept': 'text/html', 'X-Requested-With': 'XMLHttpRequest' }
      })
      const html = await response.text()
      this.sourceItemsTarget.innerHTML = html

      // Contar total de piezas disponibles
      this.updateSourceCount()
      this.updateUI()
    } catch (error) {
      console.error('Error loading source:', error)
      this.sourceItemsTarget.innerHTML = `
        <div class="p-3 text-center text-danger">
          <i class="fas fa-exclamation-triangle fa-2x mb-2"></i>
          <p>Error al cargar</p>
        </div>
      `
    }
  }

  // Cargar items de la ubicación destino (solo para previsualización)
  async loadDestination() {
    const select = this.destSelectTarget
    const option = select.options[select.selectedIndex]
    const url = option?.dataset.url

    if (!url) {
      this.destItemsTarget.innerHTML = `
        <div class="p-3 text-center text-muted">
          <i class="fas fa-arrow-up fa-2x mb-2"></i>
          <p>Selecciona una ubicación destino</p>
        </div>
      `
      this.destCountTarget.textContent = '0'
      this.updateUI()
      return
    }

    this.destItemsTarget.innerHTML = `
      <div class="p-4 text-center">
        <i class="fas fa-spinner fa-spin fa-2x"></i>
        <p class="mt-2">Cargando...</p>
      </div>
    `

    try {
      const response = await fetch(url, {
        headers: { 'Accept': 'text/html', 'X-Requested-With': 'XMLHttpRequest' }
      })
      const html = await response.text()
      this.destItemsTarget.innerHTML = html

      // Deshabilitar inputs en destino (solo lectura)
      const inputs = this.destItemsTarget.querySelectorAll('.qty-input')
      inputs.forEach(input => {
        input.disabled = true
        input.closest('tr')?.classList.add('table-light')
      })
      const buttons = this.destItemsTarget.querySelectorAll('button')
      buttons.forEach(btn => btn.disabled = true)

      this.updateDestCount()
      this.updateUI()
    } catch (error) {
      console.error('Error loading destination:', error)
      this.destItemsTarget.innerHTML = `
        <div class="p-3 text-center text-danger">
          <i class="fas fa-exclamation-triangle fa-2x mb-2"></i>
          <p>Error al cargar</p>
        </div>
      `
    }
  }

  // Refrescar destino
  refreshDestination() {
    this.loadDestination()
  }

  // Actualizar contador de origen
  updateSourceCount() {
    let total = 0
    const rows = this.sourceItemsTarget.querySelectorAll('.product-row')
    rows.forEach(row => {
      total += parseInt(row.dataset.max, 10) || 0
    })
    this.sourceCountTarget.textContent = total
  }

  // Actualizar contador de destino
  updateDestCount() {
    let total = 0
    const rows = this.destItemsTarget.querySelectorAll('.product-row')
    rows.forEach(row => {
      total += parseInt(row.dataset.max, 10) || 0
    })
    this.destCountTarget.textContent = total
  }

  // Incrementar cantidad
  incrementQty(event) {
    const row = event.target.closest('.product-row')
    const input = row.querySelector('.qty-input')
    const max = parseInt(input.max, 10) || 0
    let value = parseInt(input.value, 10) || 0
    if (value < max) {
      input.value = value + 1
      this.updateUI()
    }
  }

  // Decrementar cantidad
  decrementQty(event) {
    const row = event.target.closest('.product-row')
    const input = row.querySelector('.qty-input')
    let value = parseInt(input.value, 10) || 0
    if (value > 0) {
      input.value = value - 1
      this.updateUI()
    }
  }

  // Cuando cambia el input de cantidad
  qtyChanged(event) {
    const input = event.target
    const max = parseInt(input.max, 10) || 0
    let value = parseInt(input.value, 10) || 0

    // Validar rango
    if (value < 0) value = 0
    if (value > max) value = max
    input.value = value

    this.updateUI()
  }

  // Poner todas las cantidades al máximo
  setAllMax(event) {
    // Determinar si el click viene del panel origen
    const container = event.target.closest('.card-body') || this.sourceItemsTarget
    const inputs = container.querySelectorAll('.qty-input:not([disabled])')
    inputs.forEach(input => {
      input.value = input.max
    })
    this.updateUI()
  }

  // Limpiar todas las cantidades
  clearAll(event) {
    const container = event.target.closest('.card-body') || this.sourceItemsTarget
    const inputs = container.querySelectorAll('.qty-input:not([disabled])')
    inputs.forEach(input => {
      input.value = 0
    })
    this.updateUI()
  }

  // Obtener total de piezas a transferir
  getTotalToTransfer() {
    let total = 0
    const inputs = this.sourceItemsTarget.querySelectorAll('.qty-input')
    inputs.forEach(input => {
      total += parseInt(input.value, 10) || 0
    })
    return total
  }

  // Obtener datos de transferencia (producto -> cantidad -> item_ids)
  getTransferData() {
    const transfers = []
    const rows = this.sourceItemsTarget.querySelectorAll('.product-row')

    rows.forEach(row => {
      const input = row.querySelector('.qty-input')
      const qty = parseInt(input.value, 10) || 0
      if (qty > 0) {
        const productId = row.dataset.productId
        const itemIds = row.dataset.itemIds.split(',').map(id => parseInt(id, 10))
        // Tomar solo los primeros N item_ids (FIFO - los más antiguos están primero)
        transfers.push({
          product_id: productId,
          quantity: qty,
          item_ids: itemIds.slice(0, qty)
        })
      }
    })

    return transfers
  }

  // Actualizar UI (contador y estado del botón)
  updateUI() {
    const count = this.getTotalToTransfer()
    this.selectedCountTarget.textContent = count

    const hasSource = this.sourceSelectTarget.value !== ''
    const hasDest = this.destSelectTarget.value !== ''
    const hasSelection = count > 0
    const differentLocations = this.sourceSelectTarget.value !== this.destSelectTarget.value

    this.transferBtnTarget.disabled = !(hasSource && hasDest && hasSelection && differentLocations)

    // Mostrar advertencia si origen == destino
    if (hasSource && hasDest && !differentLocations) {
      this.showAlert('warning', 'La ubicación origen y destino deben ser diferentes')
    }
  }

  // Ejecutar transferencia
  async executeTransfer() {
    const sourceId = this.sourceSelectTarget.value
    const destId = this.destSelectTarget.value
    const transfers = this.getTransferData()
    const url = this.transferBtnTarget.dataset.url

    if (!sourceId || !destId || transfers.length === 0) return

    // Extraer todos los item_ids de las transferencias
    const allItemIds = transfers.flatMap(t => t.item_ids)

    this.transferBtnTarget.disabled = true
    this.transferBtnTarget.innerHTML = '<i class="fas fa-spinner fa-spin me-2"></i> Transfiriendo...'

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content,
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          source_location_id: sourceId,
          destination_location_id: destId,
          item_ids: allItemIds
        })
      })

      const data = await response.json()

      if (data.success) {
        this.showAlert('success', data.message)
        // Recargar ambas listas
        await this.loadSource()
        await this.loadDestination()
      } else {
        this.showAlert('danger', data.error || 'Error al transferir')
      }
    } catch (error) {
      console.error('Transfer error:', error)
      this.showAlert('danger', 'Error de conexión')
    }

    this.transferBtnTarget.disabled = false
    this.transferBtnTarget.innerHTML = '<i class="fas fa-arrow-right me-2"></i> Transferir al Destino'
    this.updateUI()
  }

  // Mostrar alerta
  showAlert(type, message) {
    const alertHtml = `
      <div class="alert alert-${type} alert-dismissible fade show" role="alert">
        ${message}
        <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
      </div>
    `
    this.alertsTarget.innerHTML = alertHtml

    // Auto-cerrar después de 5 segundos
    setTimeout(() => {
      const alert = this.alertsTarget.querySelector('.alert')
      if (alert) alert.remove()
    }, 5000)
  }
}
