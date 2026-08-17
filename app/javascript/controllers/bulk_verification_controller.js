import { Controller } from "@hotwired/stimulus"

// Selección múltiple de unidades EXACTAS de inventario para asignarles ubicación.
//
// Sólo maneja la selección en pantalla: qué casillas están marcadas, el contador
// y el estado del botón. No decide qué unidades se envían por su cuenta ni toca
// nada fuera de esta página; el servidor vuelve a filtrar los IDs recibidos.
//
// "Seleccionar todo" abarca únicamente las casillas de la página actual, que son
// las que el admin tiene a la vista.
export default class extends Controller {
  static targets = ["unit", "selectAll", "counter", "submit"]

  connect() {
    this.refresh()
  }

  toggleAll() {
    const checked = this.selectAllTarget.checked
    this.unitTargets.forEach((unit) => { unit.checked = checked })
    this.refresh()
  }

  clear() {
    this.unitTargets.forEach((unit) => { unit.checked = false })
    if (this.hasSelectAllTarget) this.selectAllTarget.checked = false
    this.refresh()
  }

  refresh() {
    const selected = this.unitTargets.filter((unit) => unit.checked).length
    const total = this.unitTargets.length

    if (this.hasCounterTarget) {
      this.counterTarget.textContent =
        `${selected} seleccionada${selected === 1 ? "" : "s"}`
    }

    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = total > 0 && selected === total
      this.selectAllTarget.indeterminate = selected > 0 && selected < total
    }

    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = selected === 0
    }
  }
}
