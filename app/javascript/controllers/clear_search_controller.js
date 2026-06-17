import { Controller } from "@hotwired/stimulus"

// Botón "limpiar" (X) para campos de búsqueda. El botón aparece sólo cuando
// hay texto y, al pulsarlo, vacía el input y lo enfoca. Si la búsqueda ya
// estaba aplicada (committed), reenvía el form para volver al catálogo completo.
export default class extends Controller {
  static targets = ["input", "button"]
  static values = { committed: Boolean }

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasButtonTarget) return
    this.buttonTarget.hidden = this.inputTarget.value.trim().length === 0
  }

  clear() {
    this.inputTarget.value = ""
    this.toggle()
    this.inputTarget.focus()

    if (this.committedValue && this.element.tagName === "FORM") {
      if (this.element.requestSubmit) {
        this.element.requestSubmit()
      } else {
        this.element.submit()
      }
    }
  }
}
