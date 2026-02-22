import { Controller } from "@hotwired/stimulus"

// Controlador Stimulus para modal de confirmación reusable (sin fallback a window.confirm).
export default class extends Controller {
  static values = { message: String }

  ask(event) {
    const msg = this.messageValue || this.element.dataset.confirmMessage || this.element.dataset.turboConfirm || this.element.getAttribute('data-confirm')
    if (!msg) return
    event.preventDefault(); event.stopPropagation()
    this.showModal(msg, () => {
      if (this.element.tagName === 'A' && this.element.href) {
        const method = this.element.dataset.turboMethod
        if (method && method.toLowerCase() !== 'get') {
          const f = document.createElement('form')
          f.method = 'post'; f.action = this.element.href
          const m = document.createElement('input'); m.type='hidden'; m.name='_method'; m.value=method; f.appendChild(m)
          const token = document.querySelector('meta[name="csrf-token"]').content
          const tk = document.createElement('input'); tk.type='hidden'; tk.name='authenticity_token'; tk.value=token; f.appendChild(tk)
          document.body.appendChild(f); f.submit()
        } else { Turbo.visit(this.element.href) }
      } else if (this.element.tagName === 'FORM') {
        this.element.submit()
      } else if (this.element.closest('form')) {
        this.element.closest('form').submit()
      }
    })
  }

  ensureModal() {
    let modal = document.getElementById('global-confirm-modal')
    if (!modal) {
      // Inyectar modal mínimo si no existe (ej. layouts alternos o peticiones Turbo parciales)
      document.body.insertAdjacentHTML('beforeend', `\n<div id="global-confirm-modal" class="confirm-modal" aria-hidden="true" role="dialog" aria-modal="true">\n  <div class="confirm-modal-backdrop" data-confirm="backdrop"></div>\n  <div class="confirm-modal-dialog" role="document">\n    <div class="confirm-modal-content">\n      <div class="confirm-modal-body"><p class="confirm-message mb-0"></p></div>\n      <div class="confirm-modal-footer d-flex gap-2 justify-content-end">\n        <button type="button" class="btn btn-sm btn-outline-secondary" data-confirm="cancel">Cancelar</button>\n        <button type="button" class="btn btn-sm btn-danger" data-confirm="ok">Confirmar</button>\n      </div>\n    </div>\n  </div>\n</div>`)
      modal = document.getElementById('global-confirm-modal')
    }
    return modal
  }

  showModal(message, onConfirm) {
    const modal = this.ensureModal()
    modal.querySelector('.confirm-message').textContent = message
    const okBtn = modal.querySelector('[data-confirm="ok"]')
    const cancelBtn = modal.querySelector('[data-confirm="cancel"]')
    const backdrop = modal.querySelector('[data-confirm="backdrop"]') || modal.querySelector('.confirm-modal-backdrop')
    const escHandler = (e) => { if (e.key === 'Escape') cleanup() }
    const cleanup = () => {
      okBtn.removeEventListener('click', okHandler)
      cancelBtn.removeEventListener('click', cancelHandler)
      backdrop?.removeEventListener('click', cancelHandler)
      document.removeEventListener('keydown', escHandler)
      modal.classList.remove('show')
      modal.setAttribute('aria-hidden','true')
    }
    const okHandler = (e) => { e.preventDefault(); onConfirm(); cleanup() }
    const cancelHandler = (e) => { e.preventDefault(); cleanup() }
    okBtn.addEventListener('click', okHandler)
    cancelBtn.addEventListener('click', cancelHandler)
    backdrop?.addEventListener('click', cancelHandler)
    document.addEventListener('keydown', escHandler)
    modal.classList.add('show')
    modal.removeAttribute('aria-hidden')
    okBtn.focus()
  }
}
