import { Controller } from "@hotwired/stimulus"

// Controlador para transferencia de inventario entre ubicaciones
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
    this.selectedItems = new Set()
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
      this.selectedItems.clear()
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

      // Contar items
      const count = this.sourceItemsTarget.querySelectorAll('.item-checkbox').length
      this.sourceCountTarget.textContent = count

      // Limpiar selección
      this.selectedItems.clear()
      this.updateUI()

      // Bind select all checkbox
      this.bindSelectAll(this.sourceItemsTarget)
    } catch (error) {
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

      // Contar items y deshabilitar checkboxes en destino
      const checkboxes = this.destItemsTarget.querySelectorAll('.item-checkbox')
      checkboxes.forEach(cb => {
        cb.disabled = true
        cb.closest('tr')?.classList.add('table-light')
      })
      const selectAll = this.destItemsTarget.querySelector('.select-all-checkbox')
      if (selectAll) selectAll.disabled = true

      this.destCountTarget.textContent = checkboxes.length
      this.updateUI()
    } catch (error) {
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

  // Bind evento a checkbox "seleccionar todo"
  bindSelectAll(container) {
    const selectAll = container.querySelector('.select-all-checkbox')
    if (selectAll) {
      selectAll.addEventListener('change', (e) => {
        const checkboxes = container.querySelectorAll('.item-checkbox')
        checkboxes.forEach(cb => {
          cb.checked = e.target.checked
          if (e.target.checked) {
            this.selectedItems.add(cb.value)
          } else {
            this.selectedItems.delete(cb.value)
          }
        })
        this.updateUI()
      })
    }
  }

  // Seleccionar todos los items del origen
  selectAllSource() {
    const checkboxes = this.sourceItemsTarget.querySelectorAll('.item-checkbox')
    checkboxes.forEach(cb => {
      cb.checked = true
      this.selectedItems.add(cb.value)
    })
    const selectAll = this.sourceItemsTarget.querySelector('.select-all-checkbox')
    if (selectAll) selectAll.checked = true
    this.updateUI()
  }

  // Deseleccionar todos los items del origen
  deselectAllSource() {
    const checkboxes = this.sourceItemsTarget.querySelectorAll('.item-checkbox')
    checkboxes.forEach(cb => {
      cb.checked = false
      this.selectedItems.delete(cb.value)
    })
    const selectAll = this.sourceItemsTarget.querySelector('.select-all-checkbox')
    if (selectAll) selectAll.checked = false
    this.updateUI()
  }

  // Actualizar selección cuando cambia un checkbox
  updateSelection(event) {
    const checkbox = event.target
    if (checkbox.checked) {
      this.selectedItems.add(checkbox.value)
    } else {
      this.selectedItems.delete(checkbox.value)
    }
    this.updateUI()
  }

  // Actualizar UI (contador y estado del botón)
  updateUI() {
    const count = this.selectedItems.size
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
    const itemIds = Array.from(this.selectedItems)
    const url = this.transferBtnTarget.dataset.url

    if (!sourceId || !destId || itemIds.length === 0) return

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
          item_ids: itemIds
        })
      })

      const data = await response.json()

      if (data.success) {
        this.showAlert('success', data.message)
        // Recargar ambas listas
        this.selectedItems.clear()
        await this.loadSource()
        await this.loadDestination()
        // Actualizar contadores en los selects
        this.updateSelectCounts()
      } else {
        this.showAlert('danger', data.error || 'Error al transferir')
      }
    } catch (error) {
      this.showAlert('danger', 'Error de conexión')
    }

    this.transferBtnTarget.disabled = false
    this.transferBtnTarget.innerHTML = '<i class="fas fa-arrow-right me-2"></i> Transferir al Destino'
    this.updateUI()
  }

  // Actualizar contadores en los selects (después de transferencia)
  updateSelectCounts() {
    // Esto requeriría recargar la página o hacer otra petición
    // Por simplicidad, sugerimos recargar
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
