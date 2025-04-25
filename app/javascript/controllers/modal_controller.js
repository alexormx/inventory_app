export default class extends HTMLElement {
  static values = { autoOpen: Boolean }
  static targets = ["focusField"]

  connect() {
    if (this.autoOpenValue && this.element.showModal) {
      console.log("✅ modal_controller conectado a:", this.element)
      this.element.showModal()

      // Espera un ciclo de event loop para enfocar correctamente
      setTimeout(() => {
        this.focusFieldTarget?.focus()
      }, 0)
    }
  }

  close() {
    this.element.close()
  }
}
