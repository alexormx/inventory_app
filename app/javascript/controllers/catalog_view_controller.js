import { Controller } from "@hotwired/stimulus"

// Controla el toggle entre vista grid y lista en el catálogo
export default class extends Controller {
  static targets = ["gridBtn", "listBtn"]
  static values = { view: { type: String, default: "grid" } }

  connect() {
    // Restaurar vista desde localStorage
    const savedView = localStorage.getItem("catalogView") || "grid"
    this.viewValue = savedView
    this.applyView()
  }

  setGrid() {
    this.viewValue = "grid"
    this.applyView()
    this.savePreference()
  }

  setList() {
    this.viewValue = "list"
    this.applyView()
    this.savePreference()
  }

  applyView() {
    const grid = document.getElementById("product-grid-content")
    if (!grid) return

    // Toggle clases en el grid
    if (this.viewValue === "list") {
      grid.classList.add("list-view")
      grid.classList.remove("row-cols-2", "row-cols-sm-2", "row-cols-md-3", "row-cols-lg-4", "row-cols-xl-5")
      grid.classList.add("row-cols-1")
      this.listBtnTarget?.classList.add("active")
      this.gridBtnTarget?.classList.remove("active")
    } else {
      grid.classList.remove("list-view", "row-cols-1")
      grid.classList.add("row-cols-2", "row-cols-sm-2", "row-cols-md-3", "row-cols-lg-4", "row-cols-xl-5")
      this.gridBtnTarget?.classList.add("active")
      this.listBtnTarget?.classList.remove("active")
    }
  }

  savePreference() {
    localStorage.setItem("catalogView", this.viewValue)
  }

  // Re-aplicar vista cuando Turbo actualiza el frame
  viewValueChanged() {
    this.applyView()
  }
}
