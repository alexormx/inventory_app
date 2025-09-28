import { Controller } from "@hotwired/stimulus"

// data-controller="shipment-guard"
// data-shipment-guard-paid-value="true|false"
// data-shipment-guard-credit-value="true|false"
// targets: warning
export default class extends Controller {
  static values = {
    paid: Boolean,
    credit: Boolean
  }
  static targets = ["warning"]

  onStatusChange(event) {
    const value = event.target.value // pending | shipped | delivered | canceled | returned
    const needsAuth = value === "shipped" || value === "delivered"
    const allowed = this.paidValue || this.creditValue

    if (needsAuth && !allowed) {
      this.showWarning()
    } else {
      this.hideWarning()
    }
  }

  showWarning() {
    if (this.hasWarningTarget) {
      this.warningTarget.classList.remove("d-none")
    }
  }

  hideWarning() {
    if (this.hasWarningTarget) {
      this.warningTarget.classList.add("d-none")
    }
  }
}
