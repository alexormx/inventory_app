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
      })
  }
}