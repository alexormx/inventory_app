import { Controller } from "@hotwired/stimulus"

// Submits one catalog form per interaction. Turbo owns navigation, frame
// history and the native [busy] state; this controller only handles immediate
// versus debounced form submission and therefore installs no global listeners.
export default class extends Controller {
  connect() {
    this.debounceDelay = 500
    this.debounceTimer = null
  }

  disconnect() {
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
  }

  submit(event) {
    if (event.target.dataset.debounce === "true") return
    if (event.type === "submit" || event.target.type === "submit") return

    this.performSubmit()
  }

  debouncedSubmit(event) {
    if (event.target.dataset.debounce !== "true") return
    if (this.debounceTimer) clearTimeout(this.debounceTimer)

    this.debounceTimer = setTimeout(() => this.performSubmit(), this.debounceDelay)
  }

  performSubmit() {
    this.element.requestSubmit()
  }
}
