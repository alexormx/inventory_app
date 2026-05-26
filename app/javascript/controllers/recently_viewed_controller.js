import { Controller } from "@hotwired/stimulus"

// Tracks the last N product slugs the user visited and renders a
// horizontal strip on the catalog page. Pure client-side via
// localStorage — no backend roundtrip, no privacy concern.
//
// Two modes:
//   data-recently-viewed-mode-value="track" → on product show; pushes
//     the current product's data into storage on connect.
//   data-recently-viewed-mode-value="display" → on catalog index;
//     hydrates the strip from storage and renders compact cards.
export default class extends Controller {
  static targets = ["container"]
  static values = {
    mode: String,
    slug: String,
    name: String,
    image: String,
    price: String,
    productPath: String,
    catalogPath: String,
    max: { type: Number, default: 10 }
  }

  static STORAGE_KEY = "pasatiempos:recentlyViewed:v1"

  connect() {
    if (this.modeValue === "track") {
      this.track()
    } else if (this.modeValue === "display") {
      this.render()
    }
  }

  track() {
    if (!this.slugValue) return
    const list = this.read()
    const entry = {
      slug: this.slugValue,
      name: this.nameValue,
      image: this.imageValue,
      price: this.priceValue,
      path: this.productPathValue,
      at: Date.now()
    }
    const deduped = [entry, ...list.filter(e => e.slug !== entry.slug)]
    const trimmed = deduped.slice(0, this.maxValue)
    this.write(trimmed)
  }

  render() {
    const list = this.read()
    if (!list.length) {
      this.element.hidden = true
      return
    }
    // On catalog landings, prefer to hide entries the user is already
    // looking at by URL filter (best-effort, not perfect)
    const here = window.location.pathname
    const visible = list.filter(e => e.path !== here)
    if (!visible.length) {
      this.element.hidden = true
      return
    }

    const container = this.hasContainerTarget ? this.containerTarget : this.element
    container.innerHTML = visible.map(e => this.cardHtml(e)).join("")
    this.element.hidden = false
  }

  cardHtml(e) {
    const safeName = this.escapeHtml(e.name || "")
    const safePrice = this.escapeHtml(e.price || "")
    const safeImage = this.escapeHtml(e.image || "")
    const safePath = this.escapeHtml(e.path || "#")
    return `
      <a class="recently-viewed-card" href="${safePath}" title="${safeName}">
        <div class="recently-viewed-thumb">
          ${safeImage ? `<img src="${safeImage}" alt="${safeName}" loading="lazy">` : `<i class="fas fa-image text-muted"></i>`}
        </div>
        <div class="recently-viewed-meta">
          <span class="recently-viewed-name">${safeName}</span>
          ${safePrice ? `<span class="recently-viewed-price text-danger fw-bold">${safePrice}</span>` : ""}
        </div>
      </a>
    `
  }

  clear() {
    this.write([])
    this.render()
  }

  read() {
    try {
      const raw = window.localStorage.getItem(this.constructor.STORAGE_KEY)
      const list = raw ? JSON.parse(raw) : []
      return Array.isArray(list) ? list : []
    } catch (_e) {
      return []
    }
  }

  write(list) {
    try {
      window.localStorage.setItem(this.constructor.STORAGE_KEY, JSON.stringify(list))
    } catch (_e) {
      // Storage full or disabled — best-effort, ignore.
    }
  }

  escapeHtml(s) {
    return String(s)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }
}
