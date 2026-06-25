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
    this.clearAllInputs()
    if (this.hasInputTarget) this.inputTarget.focus()

    if (this.committedValue && this.element.tagName === "FORM") {
      if (this.element.requestSubmit) {
        this.element.requestSubmit()
      } else {
        this.element.submit()
      }
    }
  }

  // Usado por enlaces de "Limpiar búsqueda" fuera de un form (ej. el resumen
  // de resultados). El header del sitio es data-turbo-permanent, así que sus
  // inputs no se re-renderizan al navegar y conservarían el texto; los vaciamos
  // explícitamente antes de que Turbo siga el enlace.
  clearAll() {
    this.clearAllInputs()
  }

  // Vacía todos los campos de búsqueda de la página y notifica a sus
  // controladores para que oculten su botón "X".
  clearAllInputs() {
    document.querySelectorAll('input[name="q"]').forEach((input) => {
      input.value = ""
      input.dispatchEvent(new Event("input", { bubbles: true }))
    })
  }
}
