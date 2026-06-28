import { Controller } from "@hotwired/stimulus"

// Sondea un endpoint JSON cada `interval` ms mientras `active` sea true y, al
// recibir `done: true`, recarga la página completa. Útil para procesos de fondo
// (p.ej. enriquecimiento con IA): la vista pasa sola de "Generando…" al
// resultado final sin que el usuario tenga que dar F5.
export default class extends Controller {
  static values = {
    url: String,
    interval: { type: Number, default: 3000 },
    active: Boolean,
  }

  connect() {
    if (this.activeValue) this.start()
  }

  disconnect() {
    this.stop()
  }

  start() {
    this.stop()
    this.timer = window.setInterval(() => this.check(), this.intervalValue)
  }

  stop() {
    if (!this.timer) return
    window.clearInterval(this.timer)
    this.timer = null
  }

  check() {
    fetch(this.urlValue, { headers: { Accept: "application/json" } })
      .then((res) => res.json())
      .then((state) => {
        if (state.done) {
          this.stop()
          window.location.reload()
        }
      })
      .catch(() => {})
  }
}
