import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { productId: Number, condition: String }
  static targets = ["quantity", "lineTotal"]

  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]').content
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

  updateQuantity(qty) {
    this.element.querySelector('.cart-qty-group')?.classList.add('loading')
    fetch(`/cart_items/${this.productIdValue}`, {
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
      .then(res => res.json())
      .then(data => {
        if (this.hasQuantityTarget) {
          this.quantityTarget.value = data.quantity
        }
        if (this.hasLineTotalTarget) {
          let html = `<span class=\"line-total-amount\">${data.line_total}</span>`
          if (data.item_pending > 0) {
            const pendingLabel = data.item_pending_type === 'preorder' ? 'preventa' : 'sobre pedido'
            html += `<div class=\"small text-muted mt-1 line-split-detail\"><span class=\"immediate-count\">${data.item_immediate}</span> inmediata(s) · <span class=\"pending-count\">${data.item_pending}</span> ${pendingLabel}</div>`
          }
          this.lineTotalTarget.innerHTML = html
        }
        // Actualizar badge de pendientes del ítem
        if (typeof data.product_id !== 'undefined') {
          const badge = document.getElementById(`pending-badge-${data.product_id}`)
          if (data.item_pending > 0) {
            const label = data.item_pending_type === 'preorder' ? 'Preventa' : 'Sobre pedido'
            if (badge) {
              // Actualizar número
              const countSpan = badge.querySelector('.pending-count')
              if (countSpan) countSpan.textContent = data.item_pending
              if (data.item_pending_type === 'preorder') {
                let posSpan = badge.querySelector('.preorder-position')
                if (data.item_preorder_position) {
                  if (!posSpan) {
                    badge.innerHTML += ` · Posición <span class=\"preorder-position\">${data.item_preorder_position}</span>`
                  } else {
                    posSpan.textContent = data.item_preorder_position
                  }
                }
              }
              badge.firstChild.textContent = `${label}: `
            }
          } else if (badge) {
            badge.remove()
          }
        }
        const cartTotalEl = document.getElementById('cart-total')
        if (cartTotalEl) cartTotalEl.textContent = data.cart_total
        const summarySubtotal = document.getElementById('summary-subtotal')
        if (summarySubtotal && data.subtotal) summarySubtotal.textContent = data.subtotal
        const summaryTax = document.getElementById('summary-tax')
        const summaryTaxRow = document.getElementById('summary-tax-row')
        if (summaryTax && data.tax_amount) summaryTax.textContent = data.tax_amount
        if (summaryTaxRow && typeof data.tax_enabled !== 'undefined') {
          if (data.tax_enabled) summaryTaxRow.classList.remove('d-none')
          else summaryTaxRow.classList.add('d-none')
        }
        const summaryShipping = document.getElementById('summary-shipping')
        if (summaryShipping && data.shipping_cost) summaryShipping.textContent = data.shipping_cost
        const summaryGrand = document.getElementById('summary-grand-total')
        if (summaryGrand && data.grand_total) summaryGrand.textContent = data.grand_total
        const badge = document.getElementById('cart-count')
        if (badge) badge.textContent = data.total_items
        const itemCount = document.getElementById('cart-item-count')
        if (itemCount) itemCount.textContent = data.total_items
        // Actualizar resumen de pendientes
        const pendingLi = document.getElementById('cart-pending-summary')
        if (pendingLi && typeof data.summary_pending_total !== 'undefined') {
          if (data.summary_pending_total > 0) {
            let parts = []
            if (data.summary_preorder_total > 0) parts.push(`Preventa: ${data.summary_preorder_total}`)
            if (data.summary_backorder_total > 0) parts.push(`Sobre pedido: ${data.summary_backorder_total}`)
            pendingLi.classList.remove('d-none')
            pendingLi.innerHTML = `<span>Pendientes (${data.summary_pending_total})</span><span class="small">${parts.join(' · ')}</span>`
            pendingLi.classList.add('d-flex','justify-content-between','text-warning')
          } else {
            pendingLi.classList.add('d-none')
          }
        }
        // Si vienen totales extendidos (destroy path), refrescarlos
        if (data.subtotal) {
          const summarySubtotal = document.getElementById('summary-subtotal'); if (summarySubtotal) summarySubtotal.textContent = data.subtotal
        }
        if (data.tax_amount) {
          const summaryTax = document.getElementById('summary-tax'); if (summaryTax) summaryTax.textContent = data.tax_amount
          const summaryTaxRow = document.getElementById('summary-tax-row'); if (summaryTaxRow && typeof data.tax_enabled !== 'undefined') { data.tax_enabled ? summaryTaxRow.classList.remove('d-none') : summaryTaxRow.classList.add('d-none') }
        }
        if (data.shipping_cost) { const summaryShipping = document.getElementById('summary-shipping'); if (summaryShipping) summaryShipping.textContent = data.shipping_cost }
        if (data.grand_total) { const summaryGrand = document.getElementById('summary-grand-total'); if (summaryGrand) summaryGrand.textContent = data.grand_total }
      })
      .finally(()=>{
        this.element.querySelector('.cart-qty-group')?.classList.remove('loading')
      })
  }
}