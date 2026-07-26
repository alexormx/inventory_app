import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { productId: Number, condition: String }
  static targets = ["quantity", "lineTotal", "mobileLineTotal"]

  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]').content
    this.requestInFlight = false
    // Default condition to brand_new if not set
    if (!this.conditionValue) this.conditionValue = 'brand_new'
  }

  increase() {
    const qty = parseInt(this.quantityTarget.value || 0) + 1
    this.updateQuantity(qty)
  }

  decrease() {
    let qty = parseInt(this.quantityTarget.value || 0) - 1
    if (qty < 1) qty = 1
    this.updateQuantity(qty)
  }

  quantityChanged() {
    let qty = parseInt(this.quantityTarget.value || 0)
    if (isNaN(qty) || qty < 1) qty = 1
    this.updateQuantity(qty)
  }

  async updateQuantity(qty) {
    if (this.requestInFlight) return

    this.requestInFlight = true
    const group = this.element.querySelector('.cart-qty-group')
    const controls = Array.from(group?.querySelectorAll('button, input') || [])
    const disabledBefore = new Map(controls.map(control => [control, control.disabled]))
    controls.forEach(control => { control.disabled = true })
    group?.classList.add('loading')
    let responseData = null

    try {
      const response = await fetch(`/cart_items/${this.productIdValue}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': this.csrfToken,
          'Accept': 'application/json'
        },
        body: JSON.stringify({
          product_id: this.productIdValue,
          quantity: qty,
          condition: this.conditionValue
        })
      })
      const data = await response.json().catch(() => ({}))
      if (!response.ok) throw new Error(data.error || 'No fue posible actualizar la cantidad.')

      responseData = data
      this.applySuccessfulUpdate(data)
    } catch (error) {
      this.showError(error.message || 'No fue posible actualizar la cantidad.')
    } finally {
      disabledBefore.forEach((disabled, control) => { control.disabled = disabled })
      if (responseData) this.refreshQuantityControls(responseData)
      group?.classList.remove('loading')
      this.requestInFlight = false
    }
  }

  applySuccessfulUpdate(data) {
    if (this.hasQuantityTarget) this.quantityTarget.value = data.quantity

    if (this.hasLineTotalTarget) {
      const parts = []
      if (data.item_immediate > 0) parts.push(`${data.item_immediate} inmediata(s)`)
      if (data.item_in_transit > 0) parts.push(`${data.item_in_transit} en tránsito`)
      if (data.item_pending > 0) {
        const pendingLabel = data.item_pending_type === 'preorder' ? 'preventa' : 'sobre pedido'
        parts.push(`${data.item_pending} ${pendingLabel}`)
      }
      this.lineTotalTarget.innerHTML = `<span class="line-total-amount">${data.line_total}</span>${parts.length ? `<div class="small text-muted mt-1 line-split-detail">${parts.join(' · ')}</div>` : ''}`
    }
    if (this.hasMobileLineTotalTarget) this.mobileLineTotalTarget.textContent = data.line_total

    this.updateText('cart-total', data.cart_total)
    this.updateText('summary-subtotal', data.subtotal)
    this.updateText('summary-tax', data.tax_amount)
    this.updateText('summary-grand-total', data.subtotal_with_tax || data.subtotal)
    this.updateText('cart-count', data.total_items)
    this.updateText('cart-item-count', data.total_items)

    const summaryTaxRow = document.getElementById('summary-tax-row')
    if (summaryTaxRow && typeof data.tax_enabled !== 'undefined') {
      summaryTaxRow.classList.toggle('d-none', !data.tax_enabled)
    }
    this.updatePendingSummary(data)
  }

  updatePendingSummary(data) {
    const pendingLi = document.getElementById('cart-pending-summary')
    if (!pendingLi || typeof data.summary_pending_total === 'undefined') return

    if (data.summary_pending_total <= 0) {
      pendingLi.className = 'd-none'
      pendingLi.replaceChildren()
      return
    }

    const parts = []
    if (data.summary_in_transit_total > 0) parts.push(`En tránsito: ${data.summary_in_transit_total}`)
    if (data.summary_preorder_total > 0) parts.push(`Preventa: ${data.summary_preorder_total}`)
    if (data.summary_backorder_total > 0) parts.push(`Sobre pedido: ${data.summary_backorder_total}`)
    pendingLi.className = 'd-flex justify-content-between text-warning'

    const label = document.createElement('span')
    label.textContent = `Pendientes (${data.summary_pending_total})`
    const detail = document.createElement('span')
    detail.className = 'small'
    detail.textContent = parts.join(' · ')
    pendingLi.replaceChildren(label, detail)
  }

  refreshQuantityControls(data) {
    if (!this.hasQuantityTarget) return

    const qty = Number(data.quantity)
    const decrease = this.element.querySelector('[data-action~="click->cart-item#decrease"]')
    const increase = this.element.querySelector('[data-action~="click->cart-item#increase"]')
    if (decrease) decrease.disabled = qty <= 1
    if (increase) increase.disabled = data.can_increase === false
  }

  updateText(id, value) {
    const element = document.getElementById(id)
    if (element && value !== null && typeof value !== 'undefined') element.textContent = value
  }

  showError(message) {
    const stack = document.getElementById('flash-stack')
    if (!stack) return

    const alert = document.createElement('div')
    alert.className = 'alert alert-danger alert-dismissible fade show flash-message shadow'
    alert.setAttribute('role', 'alert')
    alert.dataset.timeout = '5000'
    alert.textContent = message
    stack.appendChild(alert)
  }
}
