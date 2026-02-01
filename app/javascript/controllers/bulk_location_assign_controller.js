import { Controller } from "@hotwired/stimulus"

// Controlador para asignación masiva de ubicación a inventario
// Maneja grupos colapsables por producto, selección parcial por cantidad, y submit
export default class extends Controller {
  static targets = [
    "productGroup",    // Cada grupo de producto
    "quantityInput",   // Input numérico para cantidad a asignar
    "checkbox",        // Checkbox de cada grupo
    "selectAll",       // Checkbox "seleccionar todo"
    "counter",         // Contador de items seleccionados
    "submitBtn",       // Botón de submit
    "locationInput"    // Campo hidden de ubicación seleccionada
  ]

  connect() {
    this._updateCounter()
    this._updateSubmitState()
  }

  // Toggle colapsar/expandir un grupo de producto
  toggleGroup(event) {
    const header = event.currentTarget
    const group = header.closest('[data-bulk-location-assign-target="productGroup"]')
    const content = group.querySelector('.product-group-content')
    const icon = header.querySelector('.toggle-icon')

    if (content.classList.contains('collapsed')) {
      content.classList.remove('collapsed')
      content.style.display = 'block'
      if (icon) icon.classList.replace('fa-chevron-right', 'fa-chevron-down')
    } else {
      content.classList.add('collapsed')
      content.style.display = 'none'
      if (icon) icon.classList.replace('fa-chevron-down', 'fa-chevron-right')
    }
  }

  // Expandir todos los grupos
  expandAll() {
    this.productGroupTargets.forEach(group => {
      const content = group.querySelector('.product-group-content')
      const icon = group.querySelector('.toggle-icon')
      if (content) {
        content.classList.remove('collapsed')
        content.style.display = 'block'
      }
      if (icon) icon.classList.replace('fa-chevron-right', 'fa-chevron-down')
    })
  }

  // Colapsar todos los grupos
  collapseAll() {
    this.productGroupTargets.forEach(group => {
      const content = group.querySelector('.product-group-content')
      const icon = group.querySelector('.toggle-icon')
      if (content) {
        content.classList.add('collapsed')
        content.style.display = 'none'
      }
      if (icon) icon.classList.replace('fa-chevron-down', 'fa-chevron-right')
    })
  }

  // Seleccionar/deseleccionar todos los productos
  toggleSelectAll(event) {
    const isChecked = event.currentTarget.checked
    this.checkboxTargets.forEach(cb => {
      cb.checked = isChecked
    })
    this._updateCounter()
    this._updateSubmitState()
  }

  // Cuando cambia un checkbox individual
  checkboxChanged() {
    this._updateCounter()
    this._updateSubmitState()
    this._updateSelectAllState()
  }

  // Cuando cambia el input de cantidad
  quantityChanged(event) {
    const input = event.currentTarget
    const max = parseInt(input.max, 10) || 0
    let value = parseInt(input.value, 10) || 0

    // Validar rango
    if (value < 0) value = 0
    if (value > max) value = max
    input.value = value

    // Si el valor es > 0, marcar el checkbox automáticamente
    const group = input.closest('[data-bulk-location-assign-target="productGroup"]')
    const checkbox = group?.querySelector('[data-bulk-location-assign-target="checkbox"]')
    if (checkbox) {
      checkbox.checked = value > 0
    }

    this._updateCounter()
    this._updateSubmitState()
    this._updateSelectAllState()
  }

  // Asignar todo el inventario de un producto
  assignAll(event) {
    const group = event.currentTarget.closest('[data-bulk-location-assign-target="productGroup"]')
    const input = group?.querySelector('[data-bulk-location-assign-target="quantityInput"]')
    const checkbox = group?.querySelector('[data-bulk-location-assign-target="checkbox"]')

    if (input) {
      input.value = input.max
      if (checkbox) checkbox.checked = true
      this._updateCounter()
      this._updateSubmitState()
    }
  }

  // Limpiar cantidad de un producto
  clearQuantity(event) {
    const group = event.currentTarget.closest('[data-bulk-location-assign-target="productGroup"]')
    const input = group?.querySelector('[data-bulk-location-assign-target="quantityInput"]')
    const checkbox = group?.querySelector('[data-bulk-location-assign-target="checkbox"]')

    if (input) {
      input.value = 0
      if (checkbox) checkbox.checked = false
      this._updateCounter()
      this._updateSubmitState()
    }
  }

  // Evento cuando se selecciona una ubicación (desde location-suggest)
  locationSelected(event) {
    this._updateSubmitState()
  }

  // Actualizar contador de items seleccionados
  _updateCounter() {
    if (!this.hasCounterTarget) return

    let totalSelected = 0
    this.productGroupTargets.forEach(group => {
      const checkbox = group.querySelector('[data-bulk-location-assign-target="checkbox"]')
      const input = group.querySelector('[data-bulk-location-assign-target="quantityInput"]')
      if (checkbox?.checked && input) {
        totalSelected += parseInt(input.value, 10) || 0
      }
    })

    this.counterTarget.textContent = totalSelected
    this.counterTarget.classList.toggle('text-primary', totalSelected > 0)
    this.counterTarget.classList.toggle('text-muted', totalSelected === 0)
  }

  // Actualizar estado del botón submit
  _updateSubmitState() {
    if (!this.hasSubmitBtnTarget) return

    const hasLocation = this.hasLocationInputTarget && this.locationInputTarget.value.trim() !== ''
    const hasSelection = this._getSelectedCount() > 0

    this.submitBtnTarget.disabled = !(hasLocation && hasSelection)
  }

  // Actualizar estado del checkbox "seleccionar todo"
  _updateSelectAllState() {
    if (!this.hasSelectAllTarget) return

    const total = this.checkboxTargets.length
    const checked = this.checkboxTargets.filter(cb => cb.checked).length

    this.selectAllTarget.checked = checked === total && total > 0
    this.selectAllTarget.indeterminate = checked > 0 && checked < total
  }

  // Obtener conteo de items seleccionados
  _getSelectedCount() {
    let count = 0
    this.productGroupTargets.forEach(group => {
      const checkbox = group.querySelector('[data-bulk-location-assign-target="checkbox"]')
      const input = group.querySelector('[data-bulk-location-assign-target="quantityInput"]')
      if (checkbox?.checked && input) {
        count += parseInt(input.value, 10) || 0
      }
    })
    return count
  }

  // Preparar datos del formulario antes de submit
  prepareSubmit(event) {
    // Deshabilitar inputs de productos no seleccionados para no enviarlos
    this.productGroupTargets.forEach(group => {
      const checkbox = group.querySelector('[data-bulk-location-assign-target="checkbox"]')
      const input = group.querySelector('[data-bulk-location-assign-target="quantityInput"]')
      if (input) {
        input.disabled = !checkbox?.checked || parseInt(input.value, 10) <= 0
      }
    })
  }
}
