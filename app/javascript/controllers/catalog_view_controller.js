import { Controller } from "@hotwired/stimulus"

// Controla el toggle entre vista grid y lista en el catálogo.
// Siempre arranca en grid; el cambio a lista vive dentro de la sesión actual
// (no se persiste entre cargas para que la primera impresión sea consistente).
export default class extends Controller {
  static targets = ["gridBtn", "listBtn"]
  static values = { view: { type: String, default: "grid" } }

  connect() {
    this.viewValue = "grid"
    this.applyView()

    // Cuando Turbo reemplaza el contenido del frame, el DOM del grid cambia.
    // Reaplicamos la vista actual para que el modo elegido se mantenga al filtrar.
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
  }

  setList() {
    this.viewValue = "list"
    this.applyView()
  }

  applyView() {
    const grid = document.getElementById("product-grid-content")
    if (!grid) return

    const gridCols = ["row-cols-1", "row-cols-sm-2", "row-cols-md-3", "row-cols-lg-4", "row-cols-xl-5"]

    if (this.viewValue === "list") {
      grid.classList.add("list-view")
      gridCols.forEach((cls) => grid.classList.remove(cls))
      grid.classList.add("row-cols-1")
      if (this.hasListBtnTarget) this.listBtnTarget.classList.add("active")
      if (this.hasGridBtnTarget) this.gridBtnTarget.classList.remove("active")
    } else {
      grid.classList.remove("list-view")
      gridCols.forEach((cls) => grid.classList.add(cls))
      if (this.hasGridBtnTarget) this.gridBtnTarget.classList.add("active")
      if (this.hasListBtnTarget) this.listBtnTarget.classList.remove("active")
    }
  }

  viewValueChanged() {
    this.applyView()
  }
}
