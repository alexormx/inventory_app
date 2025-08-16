import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onSubmitEnd = this.onSubmitEnd.bind(this)
    document.addEventListener('turbo:submit-end', this.onSubmitEnd)
  }

  disconnect() {
    document.removeEventListener('turbo:submit-end', this.onSubmitEnd)
  }

  onSubmitEnd(e) {
    if (e.detail && e.detail.success) {
      const el = document.getElementById('shipment_modal')
      if (el) el.innerHTML = ''
    }
  }
}
