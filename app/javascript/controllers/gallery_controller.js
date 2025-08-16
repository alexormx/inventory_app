import { Controller } from "@hotwired/stimulus"

// Reproduce la lógica de app/javascript/custom/gallery.js como Stimulus controller
export default class extends Controller {
  static targets = ["mainImage", "thumbnail", "modal", "modalImage", "nextBtn", "prevBtn"]

  connect() {
    this.thumbnails = this.thumbnailTargets || []
    if (!this.mainImageTarget || this.thumbnails.length === 0) return

    this.currentIndex = 0

    // bind methods
    this.showNext = this.showNext.bind(this)
    this.showPrev = this.showPrev.bind(this)

    // setup listeners
    this.mainImageTarget.addEventListener('click', () => this.openModal())
    this.thumbnails.forEach((thumb, i) => thumb.addEventListener('click', () => this.updateMainImage(i)))
    this.nextBtnTarget?.addEventListener('click', this.showNext)
    this.prevBtnTarget?.addEventListener('click', this.showPrev)

    // init
    this.updateMainImage(0)
  }

  disconnect() {
    // limpiar listeners para evitar duplicados si el controller se reconecta
    this.mainImageTarget?.removeEventListener('click', () => this.openModal())
    this.thumbnails.forEach((thumb, i) => thumb.removeEventListener('click', () => this.updateMainImage(i)))
    this.nextBtnTarget?.removeEventListener('click', this.showNext)
    this.prevBtnTarget?.removeEventListener('click', this.showPrev)
  }

  updateMainImage(index) {
    const thumb = this.thumbnails[index]
    if (!thumb) return

    const src = thumb.dataset.large || thumb.src
    this.mainImageTarget.src = src
    this.mainImageTarget.alt = thumb.alt || ''
    this.mainImageTarget.dataset.index = index
    this.currentIndex = index

    this.thumbnails.forEach(t => t.classList.remove('selected-thumbnail'))
    thumb.classList.add('selected-thumbnail')
  }

  openModal() {
    if (!this.modalTarget || !this.modalImageTarget) return
    this.modalImageTarget.src = this.mainImageTarget.src
    // Usa Bootstrap modal si está disponible
    if (window.bootstrap && this.modalTarget) {
      new window.bootstrap.Modal(this.modalTarget).show()
    }
  }

  showNext() {
    const newIndex = (this.currentIndex + 1) % this.thumbnails.length
    this.updateMainImage(newIndex)
  }

  showPrev() {
    const newIndex = (this.currentIndex - 1 + this.thumbnails.length) % this.thumbnails.length
    this.updateMainImage(newIndex)
  }
}
