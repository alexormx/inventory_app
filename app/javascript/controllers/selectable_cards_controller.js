import { Controller } from "@hotwired/stimulus"

// Resalta la tarjeta/label del radio seleccionado dentro del contenedor.
// Reemplaza el JS inline duplicado en el checkout (dirección, envío, pago).
//
// Uso:
//   data-controller="selectable-cards"
//   data-action="change->selectable-cards#select"
//   data-selectable-cards-active-class-value="border-primary border-2"  (opcional)
//   data-selectable-cards-target-selector-value="label"                 (opcional)
export default class extends Controller {
  static values = {
    targetSelector: { type: String, default: "label" },
    activeClass: { type: String, default: "border-primary border-2" }
  }

  connect() {
    this.radios = Array.from(this.element.querySelectorAll('input[type="radio"]'))
    const checked = this.radios.find((r) => r.checked)
    if (checked) this.highlight(checked)
  }

  select(event) {
    const radio = event.target
    if (!radio.matches('input[type="radio"]')) return
    this.highlight(radio)
  }

  highlight(radio) {
    const classes = this.activeClassValue.split(" ").filter(Boolean)
    this.radios.forEach((r) => {
      const el = r.closest(this.targetSelectorValue)
      if (el) el.classList.remove(...classes)
    })
    const target = radio.closest(this.targetSelectorValue)
    if (target) target.classList.add(...classes)
  }
}
