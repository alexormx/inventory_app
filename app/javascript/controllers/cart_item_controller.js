import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { productId: Number }
  static targets = ["quantity", "lineTotal"]

  connect() {
    this.csrfToken = document.querySelector('meta[name="csrf-token"]').content
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
      body: JSON.stringify({ product_id: this.productIdValue, quantity: qty })
    })
      .then(res => res.json())
      .then(data => {
        this.quantityTarget.value = data.quantity
        if (this.lineTotalTarget) {
          this.lineTotalTarget.textContent = data.line_total
        }
        const cartTotalEl = document.getElementById('cart-total')
        if (cartTotalEl) cartTotalEl.textContent = data.cart_total
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
      })
      .finally(()=>{
        this.element.querySelector('.cart-qty-group')?.classList.remove('loading')
      })
  }
}