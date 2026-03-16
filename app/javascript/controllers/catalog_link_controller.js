import { Controller } from "@hotwired/stimulus"

// Manages product selection for catalog item linking.
// Works with product-search controller: listens for product-search:selected event.
export default class extends Controller {
  static targets = ["hiddenId", "selected", "selectedName", "selectedSku", "submitBtn"]

  selectProduct(event) {
    const product = event.detail
    this.hiddenIdTarget.value = product.id
    this.selectedNameTarget.textContent = product.product_name
    this.selectedSkuTarget.textContent = product.product_sku
    this.selectedTarget.classList.remove("d-none")
    this.submitBtnTarget.disabled = false
  }

  clear() {
    this.hiddenIdTarget.value = ""
    this.selectedTarget.classList.add("d-none")
    this.submitBtnTarget.disabled = true
  }
}
