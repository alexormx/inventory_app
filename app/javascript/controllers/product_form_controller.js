// app/javascript/controllers/product_form_controller.js
import { Controller } from "@hotwired/stimulus"

// Controlador para el formulario de productos con validación en tiempo real
export default class extends Controller {
  static targets = ["sellingPrice", "minPrice", "maxDiscount", "marginValue", "marginIndicator"]

  connect() {
    console.log("Product form controller connected")
    this.calculateMargin()
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
    const existingWarning = document.querySelector('.pricing-warning')
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
}
