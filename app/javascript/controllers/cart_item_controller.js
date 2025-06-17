import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["quantity", "lineTotal"]
  static values = { productId: Number, price: Number }

  connect() {
    this.updateLineTotal()
    this.updateCartTotal()
    this.updateCartCount()
  }

  increase() {
    this.quantityTarget.stepUp()
    this.quantityChanged()
  }

  decrease() {
    if (parseInt(this.quantityTarget.value) > 1) {
      this.quantityTarget.stepDown()
      this.quantityChanged()
    }
  }

  quantityChanged() {
    if (parseInt(this.quantityTarget.value) < 1) this.quantityTarget.value = 1
    this.updateLineTotal()
    this.updateCartTotal()
    this.updateCartCount()
    this.save()
  }

  updateLineTotal() {
    const quantity = parseInt(this.quantityTarget.value)
    const total = quantity * this.priceValue
    this.lineTotalTarget.textContent = this.formatCurrency(total)
    this.lineTotalTarget.dataset.amount = total
  }

  updateCartTotal() {
    const totals = Array.from(document.querySelectorAll('[data-cart-item-target="lineTotal"]'))
    const sum = totals.reduce((acc, el) => acc + (parseFloat(el.dataset.amount) || 0), 0)
    const totalCell = document.querySelector('[data-cart-total]')
    if (totalCell) totalCell.textContent = this.formatCurrency(sum)
  }

  updateCartCount() {
    const quantities = Array.from(document.querySelectorAll('[data-cart-item-target="quantity"]'))
    const count = quantities.reduce((acc, input) => acc + (parseInt(input.value) || 0), 0)
    const badge = document.getElementById('cart-count')
    if (badge) badge.textContent = count
  }

  save() {
    const quantity = parseInt(this.quantityTarget.value)
    const token = document.querySelector('meta[name="csrf-token"]').content
    fetch(`/cart_items/${this.productIdValue}`, {
      method: 'PUT',
      headers: {
        'X-CSRF-Token': token,
        'Content-Type': 'application/json',
        'Accept': 'text/vnd.turbo-stream.html'
      },
      credentials: 'same-origin',
      body: JSON.stringify({ product_id: this.productIdValue, quantity: quantity })
    })
  }

  formatCurrency(amount) {
    return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount)
  }
}
