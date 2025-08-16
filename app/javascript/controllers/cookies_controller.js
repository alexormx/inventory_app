import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.banner = document.getElementById('cookie-banner')
    this.overlay = document.getElementById('cookie-overlay')
    if (!this.banner || !this.overlay) return

    const localStatus = localStorage.getItem('cookiesAccepted')
    const sessionStatus = sessionStorage.getItem('cookiesAccepted')
    const serverAccepted = this.banner.dataset.cookiesAccepted === 'true'

    if (localStatus === 'true' || sessionStatus === 'true' || localStatus === 'false' || sessionStatus === 'false' || serverAccepted) {
      this.hideBanner()
      return
    }

    this.banner.classList.remove('d-none')
    this.overlay.style.display = 'block'
    document.body.classList.add('no-scroll')
  }

  hideBanner() {
    this.banner?.remove()
    this.overlay?.remove()
    document.body.classList.remove('no-scroll')
  }

  accept() {
    sessionStorage.setItem('cookiesAccepted', 'true')
    localStorage.setItem('cookiesAccepted', 'true')
    this.hideBanner()
    if (this.banner?.dataset?.loggedIn === 'true') {
      fetch('/accept_cookies', {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({})
      })
    }
  }

  reject() {
    sessionStorage.setItem('cookiesAccepted', 'false')
    this.hideBanner()
  }
}
