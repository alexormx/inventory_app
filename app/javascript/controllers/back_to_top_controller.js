import { Controller } from "@hotwired/stimulus"

// Botón flotante que aparece cuando scrolleas hacia abajo y vuelve al top en click.
export default class extends Controller {
  static values = { threshold: { type: Number, default: 600 } }

  connect() {
    this.onScroll = this.toggleVisibility.bind(this)
    window.addEventListener("scroll", this.onScroll, { passive: true })
    this.toggleVisibility()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
  }

  toggleVisibility() {
    if (window.scrollY > this.thresholdValue) {
      this.element.classList.add("show")
    } else {
      this.element.classList.remove("show")
    }
  }

  scrollUp(event) {
    event.preventDefault()
    window.scrollTo({ top: 0, behavior: "smooth" })
  }
}
