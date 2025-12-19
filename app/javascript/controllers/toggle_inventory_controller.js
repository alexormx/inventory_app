import { Controller } from "@hotwired/stimulus"

// Toggle inventory items visibility with button state change
export default class extends Controller {
  static targets = ["button", "frame"]
  static values = {
    url: String,
    showText: { type: String, default: "👁 Ver piezas" },
    hideText: { type: String, default: "🙈 Ocultar piezas" },
    count: { type: Number, default: 0 }
  }

  connect() {
    this.expanded = false
  }

  toggle(event) {
    event.preventDefault()

    if (this.expanded) {
      this.collapse()
    } else {
      this.expand()
    }
  }

  expand() {
    // Load content via Turbo
    const frame = this.frameTarget
    frame.src = this.urlValue

    // Update button state
    this.expanded = true
    this.updateButton()
  }

  collapse() {
    // Clear the frame content
    const frame = this.frameTarget
    frame.innerHTML = ""
    frame.removeAttribute("src")

    // Update button state
    this.expanded = false
    this.updateButton()
  }

  updateButton() {
    const btn = this.buttonTarget
    const countText = this.countValue > 0 ? ` (${this.countValue})` : ""

    if (this.expanded) {
      btn.textContent = this.hideTextValue + countText
      btn.classList.remove("btn-outline-primary")
      btn.classList.add("btn-outline-secondary")
    } else {
      btn.textContent = this.showTextValue + countText
      btn.classList.remove("btn-outline-secondary")
      btn.classList.add("btn-outline-primary")
    }
  }
}
