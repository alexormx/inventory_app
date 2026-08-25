import { Controller } from "@hotwired/stimulus"

// Tracks the last N product slugs the user visited and asks the server to
// render current public product data for the catalog's horizontal strip.
//
// Two modes:
//   data-recently-viewed-mode-value="track" → on product show; pushes
//     only the stable product slug and timestamp into storage on connect.
//   data-recently-viewed-mode-value="display" → on catalog index;
//     resolves current presentation data from the server.
export default class extends Controller {
  static targets = ["container"]
  static values = {
    mode: String,
    slug: String,
    endpoint: String,
    placeholder: String,
    max: { type: Number, default: 10 }
  }

  static V1_STORAGE_KEY = "pasatiempos:recentlyViewed:v1"
  static V2_STORAGE_KEY = "pasatiempos:recentlyViewed:v2"
  static SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/

  connect() {
    if (this.modeValue === "track") {
      this.track()
    } else if (this.modeValue === "display") {
      this.renderCurrentProducts()
    }
  }

  disconnect() {
    this.abortController?.abort()
  }

  track() {
    if (!this.slugValue) return
    const list = this.read()
    const entry = this.normalizeEntry({ slug: this.slugValue, at: Date.now() })
    if (!entry) return

    const deduped = [entry, ...list.filter(e => e.slug !== entry.slug)]
    const trimmed = deduped.slice(0, this.maxValue)
    this.write(trimmed)
  }

  async renderCurrentProducts() {
    const list = this.read()
    const container = this.hasContainerTarget ? this.containerTarget : this.element
    container.replaceChildren()
    this.element.hidden = true
    if (!list.length || !this.hasEndpointValue) return

    this.abortController?.abort()
    this.abortController = new AbortController()

    const url = new URL(this.endpointValue, window.location.origin)
    list.forEach(entry => url.searchParams.append("slugs[]", entry.slug))

    try {
      const response = await fetch(url, {
        headers: {
          "Accept": "text/html",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        signal: this.abortController.signal
      })
      if (!response.ok) throw new Error(`Recently viewed request failed: ${response.status}`)

      container.innerHTML = await response.text()
      this.element.hidden = !container.querySelector(".recently-viewed-card")
    } catch (error) {
      if (error.name === "AbortError") return

      container.replaceChildren()
      this.element.hidden = true
    }
  }

  imageError(event) {
    const image = event.currentTarget
    if (image.dataset.recentlyViewedFallbackApplied === "true") {
      const icon = document.createElement("i")
      icon.className = "fas fa-image text-muted"
      icon.setAttribute("aria-label", "Imagen no disponible")
      image.replaceWith(icon)
      return
    }

    image.closest("picture")?.querySelectorAll("source").forEach(source => source.remove())
    image.dataset.recentlyViewedFallbackApplied = "true"
    image.alt = "Imagen no disponible"
    image.removeAttribute("srcset")
    image.src = this.placeholderValue
  }

  clear() {
    this.write([])
    this.renderCurrentProducts()
  }

  read() {
    const current = this.readKey(this.constructor.V2_STORAGE_KEY)
    const legacy = this.readKey(this.constructor.V1_STORAGE_KEY)

    if (legacy !== null) {
      const migrated = this.normalizeList([...current, ...legacy])
      if (this.write(migrated)) {
        try {
          window.localStorage.removeItem(this.constructor.V1_STORAGE_KEY)
        } catch (_e) {
          // Storage disabled — best-effort, leave the legacy entry untouched.
        }
      }
      return migrated
    }

    return this.normalizeList(current)
  }

  readKey(key) {
    let raw
    try {
      raw = window.localStorage.getItem(key)
    } catch (_e) {
      return key === this.constructor.V1_STORAGE_KEY ? null : []
    }

    if (raw === null) return key === this.constructor.V1_STORAGE_KEY ? null : []

    try {
      const list = JSON.parse(raw)
      return Array.isArray(list) ? list : []
    } catch (_e) {
      return []
    }
  }

  write(list) {
    try {
      window.localStorage.setItem(this.constructor.V2_STORAGE_KEY, JSON.stringify(list))
      return true
    } catch (_e) {
      // Storage full or disabled — best-effort, ignore.
      return false
    }
  }

  normalizeList(list) {
    const seen = new Set()
    const normalized = []

    for (const candidate of list) {
      const entry = this.normalizeEntry(candidate)
      if (!entry || seen.has(entry.slug)) continue

      seen.add(entry.slug)
      normalized.push(entry)
      if (normalized.length >= this.maxValue) break
    }

    return normalized
  }

  normalizeEntry(candidate) {
    if (!candidate || typeof candidate !== "object") return null

    const slug = typeof candidate.slug === "string" ? candidate.slug.trim().toLowerCase() : ""
    const timestamp = Number(candidate.at)
    if (!slug || slug.length > 255 || !this.constructor.SLUG_PATTERN.test(slug)) return null
    if (!Number.isFinite(timestamp) || timestamp < 0) return null

    return { slug, at: Math.trunc(timestamp) }
  }
}
