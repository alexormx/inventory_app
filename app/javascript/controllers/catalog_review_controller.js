import { Controller } from "@hotwired/stimulus"

// Handles keyboard navigation and catalog-item-search:selected event forwarding
// for the catalog review one-by-one workflow.
export default class extends Controller {
  static targets = ["hiddenId", "selected", "selectedName", "selectedSku", "submitBtn"]

  connect() {
    this._onKey = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
  }

  handleKeydown(event) {
    // Skip if user is typing in an input/textarea
    if (event.target.matches("input, textarea, select")) return

    if (event.key === "ArrowLeft") {
      const prev = document.querySelector("[data-nav='prev']")
      if (prev && !prev.disabled) prev.click()
    } else if (event.key === "ArrowRight") {
      const next = document.querySelector("[data-nav='next']")
      if (next && !next.disabled) next.click()
    }
  }

  // Receives catalog-item-search:selected event for manual linking
  selectItem(event) {
    const item = event.detail
    if (!this.hasHiddenIdTarget) return

    this.hiddenIdTarget.value = item.id
    this.selectedNameTarget.textContent = item.canonical_name
    this.selectedSkuTarget.textContent = item.external_sku
    this.selectedTarget.classList.remove("d-none")
    this.submitBtnTarget.disabled = false
  }
}
