// app/javascript/controllers/product_form_controller.js
import { Controller } from "@hotwired/stimulus"

// Controlador para el formulario de productos con validación en tiempo real
export default class extends Controller {
  static targets = ["sellingPrice", "minPrice", "maxDiscount", "marginValue", "marginIndicator", "currentTab"]
  static values = { initialTab: String }

  connect() {
    this.handleTabShown = this.handleTabShown.bind(this)
    this.tabButtons.forEach((button) => button.addEventListener("shown.bs.tab", this.handleTabShown))
    this.initializeTooltips()
    this.activateInitialTab()
    this.calculateMargin()
  }

  disconnect() {
    this.tabButtons.forEach((button) => button.removeEventListener("shown.bs.tab", this.handleTabShown))
    this.disposeTooltips()
  }

  calculateMargin() {
    if (!this.hasSellingPriceTarget || !this.hasMinPriceTarget || !this.hasMaxDiscountTarget) {
      return
    }

    const sellingPrice = parseFloat(this.sellingPriceTarget.value) || 0
    const minimumPrice = parseFloat(this.minPriceTarget.value) || 0
    const maxDiscount = parseFloat(this.maxDiscountTarget.value) || 0

    if (sellingPrice <= 0) {
      this.updateMarginDisplay("--", "secondary")
      return
    }

    // Calcular precio con descuento máximo
    const priceWithMaxDiscount = sellingPrice - (sellingPrice * maxDiscount / 100)

    // Calcular margen
    const margin = ((sellingPrice - minimumPrice) / sellingPrice * 100)

    // Validar que el precio mínimo no sea menor al precio con descuento máximo
    if (minimumPrice > 0 && minimumPrice < priceWithMaxDiscount) {
      this.showWarning(`⚠️ El precio mínimo ($${minimumPrice.toFixed(2)}) es menor al precio con descuento máximo ($${priceWithMaxDiscount.toFixed(2)})`)
    } else {
      this.clearWarning()
    }

    // Actualizar indicador visual según el margen
    let color = "secondary"
    if (margin >= 40) {
      color = "success"
    } else if (margin >= 25) {
      color = "info"
    } else if (margin >= 15) {
      color = "warning"
    } else if (margin > 0) {
      color = "danger"
    }

    this.updateMarginDisplay(margin.toFixed(2), color)
  }

  updateMarginDisplay(value, colorClass) {
    if (!this.hasMarginValueTarget || !this.hasMarginIndicatorTarget) {
      return
    }

    this.marginValueTarget.textContent = value

    // Actualizar clases de color del alert
    const indicator = this.marginIndicatorTarget
    indicator.classList.remove('alert-secondary', 'alert-success', 'alert-info', 'alert-warning', 'alert-danger')
    indicator.classList.add(`alert-${colorClass}`)
  }

  showWarning(message) {
    // Mostrar advertencia temporal
    const existingWarning = this.element.querySelector('.pricing-warning')
    if (existingWarning) {
      existingWarning.remove()
    }

    const warning = document.createElement('div')
    warning.className = 'alert alert-warning alert-dismissible fade show pricing-warning mt-2'
    warning.innerHTML = `
      ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
    `

    if (this.hasMarginIndicatorTarget) {
      this.marginIndicatorTarget.insertAdjacentElement('afterend', warning)
    }
  }

  clearWarning() {
    const existingWarning = this.element.querySelector('.pricing-warning')
    if (existingWarning) {
      existingWarning.remove()
    }
  }

  handleTabShown(event) {
    const target = event.target.dataset.bsTarget
    if (!target) {
      return
    }

    const tabId = target.replace('#', '')
    if (this.hasCurrentTabTarget) {
      this.currentTabTarget.value = tabId
    }

    const url = new URL(window.location)
    url.searchParams.set('tab', tabId)
    window.history.replaceState({}, '', url)
  }

  activateInitialTab() {
    const tabId = this.currentTabTarget?.value || this.initialTabValue || 'basic'
    const selector = `[data-bs-target="#${this.escapeSelector(tabId)}"]`
    const targetButton = this.element.querySelector(selector)

    if (targetButton && window.bootstrap?.Tab) {
      window.bootstrap.Tab.getOrCreateInstance(targetButton).show()
    }
  }

  initializeTooltips() {
    if (!window.bootstrap?.Tooltip) {
      return
    }

    this.tooltips = Array.from(this.element.querySelectorAll('[data-bs-toggle="tooltip"]')).map(
      (element) => new window.bootstrap.Tooltip(element)
    )
  }

  disposeTooltips() {
    if (!this.tooltips) {
      return
    }

    this.tooltips.forEach((tooltip) => tooltip.dispose())
    this.tooltips = []
  }

  escapeSelector(value) {
    if (window.CSS?.escape) {
      return window.CSS.escape(value)
    }

    return value.replace(/([#.;?+*~':"!^$\[\]()=>|\/@])/g, "\\$1")
  }

  get tabButtons() {
    return Array.from(this.element.querySelectorAll('#productFormTabs [data-bs-toggle="tab"]'))
  }
}
