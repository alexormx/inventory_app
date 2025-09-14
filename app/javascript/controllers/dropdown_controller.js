import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "button"]

  connect() {
    this.outsideClickHandler = this.closeIfOutside.bind(this)
    document.addEventListener("click", this.outsideClickHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.outsideClickHandler)
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    const isOpen = this.menuTarget.classList.toggle("show")
    this.element.classList.toggle("show", isOpen)
    this.buttonTarget.setAttribute("aria-expanded", isOpen)
  }

  closeIfOutside(event) {
    if (!this.element.contains(event.target)) {
      this.menuTarget.classList.remove("show")
      this.element.classList.remove("show")
      if (this.hasButtonTarget) {
        this.buttonTarget.setAttribute("aria-expanded", false)
      }
    }
  }
}