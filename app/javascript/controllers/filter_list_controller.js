import { Controller } from "@hotwired/stimulus"

// Filtra client-side los items de una lista (categorías/marcas/series) según el texto del input.
export default class extends Controller {
  static targets = ["search", "list", "item"]

  filter() {
    const term = (this.hasSearchTarget ? this.searchTarget.value : "").trim().toLowerCase()
    let visible = 0

    this.itemTargets.forEach((item) => {
      const label = (item.dataset.label || item.textContent || "").toLowerCase()
      const match = term === "" || label.includes(term)
      item.style.display = match ? "" : "none"
      if (match) visible++
    })

    this.toggleEmptyMessage(visible, term)
  }

  toggleEmptyMessage(visible, term) {
    if (!this.hasListTarget) return
    let empty = this.listTarget.querySelector("[data-filter-list-empty]")
    if (visible === 0 && term !== "") {
      if (!empty) {
        empty = document.createElement("div")
        empty.setAttribute("data-filter-list-empty", "")
        empty.className = "text-muted small px-2 py-1"
        empty.textContent = "Sin coincidencias"
        this.listTarget.appendChild(empty)
      }
      empty.style.display = ""
    } else if (empty) {
      empty.style.display = "none"
    }
  }
}
