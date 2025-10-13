import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["loading"]
  
  connect() {
    this.debounceTimer = null
    this.debounceDelay = 500 // 500ms debounce for inputs
    
    // Listen to turbo:before-fetch-request to show loading
    document.addEventListener('turbo:before-fetch-request', this.showLoading.bind(this))
    // Listen to turbo:frame-render to hide loading
    document.addEventListener('turbo:frame-render', this.hideLoading.bind(this))
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
    document.removeEventListener('turbo:before-fetch-request', this.showLoading.bind(this))
    document.removeEventListener('turbo:frame-render', this.hideLoading.bind(this))
  }

  showLoading(event) {
    const frame = document.getElementById('products_grid')
    if (frame && event.detail.fetchOptions.headers['Turbo-Frame'] === 'products_grid') {
      frame.setAttribute('busy', '')
      frame.style.minHeight = frame.offsetHeight + 'px' // Prevent layout shift
    }
  }

  hideLoading(event) {
    const frame = document.getElementById('products_grid')
    if (frame) {
      frame.removeAttribute('busy')
      setTimeout(() => {
        frame.style.minHeight = ''
      }, 300)
    }
  }

  // Submit immediately for checkboxes and selects
  submit(event) {
    // Don't auto-submit if it's a debounced input
    if (event.target.dataset.debounce === "true") {
      return
    }
    
    // Don't auto-submit on submit button click
    if (event.type === "submit" || event.target.type === "submit") {
      return
    }

    this.performSubmit()
  }

  // Debounced submit for text/number inputs
  debouncedSubmit(event) {
    if (event.target.dataset.debounce !== "true") {
      return
    }

    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    this.debounceTimer = setTimeout(() => {
      this.performSubmit()
    }, this.debounceDelay)
  }

  performSubmit() {
    // Show loading indicator if we have one
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove("d-none")
    }

    // Submit the form
    this.element.requestSubmit()
  }
}
