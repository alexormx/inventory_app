import { Controller } from "@hotwired/stimulus"

// Galería de imágenes del producto: thumbnails + flechas + teclado.
export default class extends Controller {
  static targets = ["track", "thumbnails"]
  static values = { index: { type: Number, default: 0 } }

  connect() {
    this.onKeydown = this.handleKeydown.bind(this)
    this.element.addEventListener("keydown", this.onKeydown)
    this.update()
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.onKeydown)
  }

  show(event) {
    const idx = parseInt(event.currentTarget?.dataset.index, 10)
    if (Number.isNaN(idx)) return
    this.indexValue = idx
    this.update()
  }

  next() {
    const total = this.slides().length
    if (total === 0) return
    this.indexValue = (this.indexValue + 1) % total
    this.update()
  }

  prev() {
    const total = this.slides().length
    if (total === 0) return
    this.indexValue = (this.indexValue - 1 + total) % total
    this.update()
  }

  keydown(event) {
    this.handleKeydown(event)
  }

  handleKeydown(event) {
    if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.prev()
    } else if (event.key === "ArrowRight") {
      event.preventDefault()
      this.next()
    }
  }

  update() {
    const slides = this.slides()
    slides.forEach((slide, i) => {
      const active = i === this.indexValue
      slide.style.display = active ? "" : "none"
      slide.setAttribute("aria-hidden", active ? "false" : "true")
    })

    if (this.hasThumbnailsTarget) {
      const thumbs = this.thumbnailsTarget.querySelectorAll(".thumb-btn")
      thumbs.forEach((thumb, i) => {
        const active = i === this.indexValue
        thumb.classList.toggle("is-active", active)
        thumb.setAttribute("aria-current", active ? "true" : "false")
        const img = thumb.querySelector(".thumbnail-image")
        if (img) img.classList.toggle("border-primary", active)
      })
    }
  }

  slides() {
    if (!this.hasTrackTarget) return []
    return Array.from(this.trackTarget.querySelectorAll(".gallery-slide"))
  }
}
