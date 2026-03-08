import { Controller } from "@hotwired/stimulus"
import { confirmDialog } from "../lib/confirm_dialog"

// Controlador Stimulus para modal de confirmación reusable (sin fallback a window.confirm).
export default class extends Controller {
  static values = { message: String }

  async ask(event) {
    const msg = this.messageValue || this.element.dataset.confirmMessage || this.element.dataset.turboConfirm || this.element.getAttribute('data-confirm')
    if (!msg) return
    event.preventDefault(); event.stopPropagation()
    const confirmed = await confirmDialog(msg, { element: this.element })
    if (!confirmed) return

    if (this.element.tagName === 'A' && this.element.href) {
      const method = this.element.dataset.turboMethod
      if (method && method.toLowerCase() !== 'get') {
        const f = document.createElement('form')
        f.method = 'post'; f.action = this.element.href
        const m = document.createElement('input'); m.type='hidden'; m.name='_method'; m.value=method; f.appendChild(m)
        const token = document.querySelector('meta[name="csrf-token"]')?.content
        if (token) {
          const tk = document.createElement('input'); tk.type='hidden'; tk.name='authenticity_token'; tk.value=token; f.appendChild(tk)
        }
        document.body.appendChild(f); f.submit()
      } else { Turbo.visit(this.element.href) }
    } else if (this.element.tagName === 'FORM') {
      this.element.submit()
    } else if (this.element.closest('form')) {
      this.element.closest('form').submit()
    }
  }
}
