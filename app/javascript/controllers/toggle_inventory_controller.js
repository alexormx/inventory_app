import { Controller } from "@hotwired/stimulus"

// Toggle inventory items visibility with button state change
export default class extends Controller {
  static targets = ["button", "frame"]
  static values = {
    url: String,
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
    
    // Show the frame (remove Bootstrap collapse class)
    frame.classList.remove("collapse")
    frame.classList.add("show")

    // Update button state
    this.expanded = true
    this.updateButton()
  }

  collapse() {
    // Hide the frame
    const frame = this.frameTarget
    frame.classList.add("collapse")
    frame.classList.remove("show")
    
    // Clear the frame content
    frame.innerHTML = ""
    frame.removeAttribute("src")

    // Update button state
    this.expanded = false
    this.updateButton()
  }

  updateButton() {
    const btn = this.buttonTarget
    const countBadge = this.countValue > 0 ? `<span class="badge bg-primary text-white ms-1">${this.countValue}</span>` : ""

    if (this.expanded) {
      btn.innerHTML = `<i class="fa fa-eye-slash me-1"></i> Ocultar ${countBadge}`
      btn.classList.remove("btn-outline-primary")
      btn.classList.add("btn-outline-secondary")
    } else {
      btn.innerHTML = `<i class="fa fa-eye me-1"></i> Ver piezas ${countBadge}`
      btn.classList.remove("btn-outline-secondary")
      btn.classList.add("btn-outline-primary")
    }
  }
}
