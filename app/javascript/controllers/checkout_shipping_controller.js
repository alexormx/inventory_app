import { Controller } from "@hotwired/stimulus"

// Paso 2 del checkout: al cambiar el método de envío, resalta la opción y
// actualiza el resumen del pedido (costo de envío + total) sin recargar.
// Los costos provienen del servidor (Shipping::Calculator) vía methods-value.
//
// Uso:
//   data-controller="checkout-shipping"
//   data-action="change->checkout-shipping#select"
//   data-checkout-shipping-methods-value="<%= {code => {name:, cost:}} json %>"
//   data-checkout-shipping-subtotal-value="<%= cart.total %>"
export default class extends Controller {
  static values = {
    methods: Object,
    subtotal: Number,
    activeClass: { type: String, default: "border-primary border-2 bg-primary bg-opacity-10" }
  }

  connect() {
    this.radios = Array.from(this.element.querySelectorAll('input[name="shipping_method"]'))
    const checked = this.radios.find((r) => r.checked)
    if (checked) this.highlight(checked)
  }

  select(event) {
    const radio = event.target
    if (!radio.matches('input[name="shipping_method"]')) return
    this.highlight(radio)
    this.updateSummary(radio.value)
  }

  highlight(radio) {
    const classes = this.activeClassValue.split(" ").filter(Boolean)
    this.radios.forEach((r) => {
      const label = r.closest("label")
      if (label) label.classList.remove(...classes)
    })
    const label = radio.closest("label")
    if (label) label.classList.add(...classes)
  }

  updateSummary(code) {
    const method = this.methodsValue[code]
    if (!method) return

    const costEl = document.getElementById("checkout-shipping-cost")
    const nameEl = document.getElementById("checkout-shipping-method-name")
    const totalEl = document.getElementById("checkout-grand-total")

    if (costEl) {
      costEl.innerHTML = method.cost === 0
        ? '<span class="text-success">Gratis</span>'
        : this.format(method.cost)
    }
    if (nameEl) nameEl.innerHTML = `<small>(${method.name})</small>`
    if (totalEl) totalEl.textContent = this.format(this.subtotalValue + method.cost)
  }

  format(amount) {
    return "$" + amount.toLocaleString("es-MX", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
