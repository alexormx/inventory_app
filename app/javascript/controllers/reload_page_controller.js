import { Controller } from "@hotwired/stimulus"

// Recarga la página completa al conectarse. Se inyecta dentro de un turbo-frame
// (vía polling) cuando un proceso de fondo llega a su estado final, para
// reemplazar la vista "en progreso" por la vista completa ya lista.
export default class extends Controller {
  connect() {
    window.location.reload()
  }
}
