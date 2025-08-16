import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { productId: String, framePrefix: { type: String, default: 'inventory-items-frame-' } }

  onClick(event) {
    const toggle = event.currentTarget
    const productId = this.productIdValue || (toggle.id && toggle.id.replace('inventory-toggle-', ''))
    const frameId = this.framePrefixValue + productId
    const frame = document.getElementById(frameId)
    if (!frame) return

    if (frame.innerHTML.trim() !== '') {
      const items = frame.querySelector('.inventory-items')
      if (items) {
        const isHidden = items.classList.toggle('d-none')
        if (toggle.textContent) {
          toggle.textContent = isHidden ? toggle.textContent.replace('Ocultar', 'Ver') : toggle.textContent.replace('Ver', 'Ocultar')
        }
        event.preventDefault()
      }
    } else {
      const observer = new MutationObserver(() => {
        const items = frame.querySelector('.inventory-items')
        if (items) {
          if (toggle.textContent) toggle.textContent = toggle.textContent.replace('Ver', 'Ocultar')
          observer.disconnect()
        }
      })
      observer.observe(frame, { childList: true, subtree: true })
    }
  }
}
