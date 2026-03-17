import { Controller } from "@hotwired/stimulus"

// Searches supplier catalog items and dispatches selection event.
// Usage:
//   data-controller="catalog-item-search"
//   data-catalog-item-search-url-value="/admin/supplier_catalog_items/search"
// Targets:
//   data-catalog-item-search-target="input"
//   data-catalog-item-search-target="results"
// Dispatches: catalog-item-search:selected with detail = catalog item object
export default class extends Controller {
  static targets = ["input", "results"]
  static values = { url: { type: String, default: "/admin/supplier_catalog_items/search" } }

  connect() {
    this._timer = null
  }

  input() {
    const q = this.inputTarget.value.trim()
    if (q.length < 2) {
      this.resultsTarget.innerHTML = ""
      return
    }
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this.performSearch(q), 300)
  }

  performSearch(query) {
    const url = `${this.urlValue}?query=${encodeURIComponent(query)}`
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(url, { headers: { "Accept": "application/json", "X-CSRF-Token": token } })
      .then(r => { if (!r.ok) throw new Error(`HTTP ${r.status}`); return r.json() })
      .then(items => this.render(items))
      .catch(err => this.renderError(err))
  }

  render(items) {
    this.resultsTarget.innerHTML = ""
    if (!Array.isArray(items)) return this.renderError(new Error("Invalid response"))
    if (items.length === 0) {
      this.resultsTarget.innerHTML = '<div class="list-group-item text-muted small">No se encontraron artículos</div>'
      return
    }
    items.forEach(item => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "list-group-item list-group-item-action small"
      const linkedBadge = item.linked ? '<span class="badge bg-warning text-dark ms-1">ya vinculado</span>' : ""
      const img = item.main_image_url
        ? `<img src="${item.main_image_url}" class="me-2 rounded" width="36" height="36" style="object-fit:cover;">`
        : ""
      btn.innerHTML = `<div class="d-flex align-items-center">${img}<div class="flex-grow-1"><strong>${item.canonical_name}</strong>${linkedBadge}<br><small class="text-muted">${item.external_sku} · ${item.canonical_status || ""}</small></div></div>`
      btn.addEventListener("click", () => {
        this.dispatch("selected", { detail: item })
        this.resultsTarget.innerHTML = ""
        this.inputTarget.value = ""
      })
      this.resultsTarget.appendChild(btn)
    })
  }

  renderError(err) {
    this.resultsTarget.innerHTML = `<div class="list-group-item text-danger small">Error: ${err.message}</div>`
  }
}
