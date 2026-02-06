import { Controller } from "@hotwired/stimulus"

// Controla el toggle entre vista grid y lista en el catálogo
export default class extends Controller {
  static targets = ["gridBtn", "listBtn"]
  static values = { view: { type: String, default: "grid" } }

  connect() {
    this.viewValue = this.safeGetPreference() || "grid"
    this.applyView()

    // Cuando Turbo reemplaza el contenido del frame, el DOM del grid cambia.
    // Reaplicamos la vista guardada para que el usuario no "pierda" el modo lista.
    this._onTurboFrameRender = (event) => {
      if (event?.target?.id !== "products_grid") return
      this.applyView()
    }

    document.addEventListener("turbo:frame-render", this._onTurboFrameRender)
  }

  disconnect() {
    if (this._onTurboFrameRender) {
      document.removeEventListener("turbo:frame-render", this._onTurboFrameRender)
    }
  }

  setGrid() {
    this.viewValue = "grid"
    this.applyView()
    this.safeSetPreference(this.viewValue)
  }

  setList() {
    this.viewValue = "list"
    this.applyView()
    this.safeSetPreference(this.viewValue)
  }

  applyView() {
    const grid = document.getElementById("product-grid-content")
    if (!grid) return

    // Toggle clases en el grid
    if (this.viewValue === "list") {
      grid.classList.add("list-view")
      grid.classList.remove("row-cols-2", "row-cols-sm-2", "row-cols-md-3", "row-cols-lg-4", "row-cols-xl-5")
      grid.classList.add("row-cols-1")
      if (this.hasListBtnTarget) this.listBtnTarget.classList.add("active")
      if (this.hasGridBtnTarget) this.gridBtnTarget.classList.remove("active")
    } else {
      grid.classList.remove("list-view", "row-cols-1")
      grid.classList.add("row-cols-2", "row-cols-sm-2", "row-cols-md-3", "row-cols-lg-4", "row-cols-xl-5")
      if (this.hasGridBtnTarget) this.gridBtnTarget.classList.add("active")
      if (this.hasListBtnTarget) this.listBtnTarget.classList.remove("active")
    }
  }

  safeGetPreference() {
    try {
      return localStorage.getItem("catalogView")
    } catch (_) {
      return null
    }
  }

  safeSetPreference(value) {
    try {
      localStorage.setItem("catalogView", value)
    } catch (_) {
      // Sin persistencia si el storage está bloqueado.
    }
  }

  // Re-aplicar vista cuando Turbo actualiza el frame
  viewValueChanged() {
    this.applyView()
  }
}
