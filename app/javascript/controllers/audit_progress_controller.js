import { Controller } from "@hotwired/stimulus"

// Controla la UX de progreso de la auditoría.
export default class extends Controller {
  static values = { status: String }

  connect() {
    this.renderIdle()
  }

  start(event) {
    // Deja que el submit siga, pero muestra estado inmediato
    this.renderRunning()
  }

  renderIdle() {
    this.element.innerHTML = ''
  }

  renderRunning() {
    this.element.innerHTML = `\n      <div class="alert alert-info py-2 d-flex align-items-center gap-2 mb-2">\n        <span class="spinner-border spinner-border-sm"></span>\n        <strong>Ejecutando auditoría...</strong> <span id="audit-progress-text" class="small text-muted ms-2">iniciando</span>\n      </div>\n    `
  }
}
