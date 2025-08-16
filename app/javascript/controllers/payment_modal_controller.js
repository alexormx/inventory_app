import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.onFrameLoad = this.onFrameLoad.bind(this)
    document.addEventListener('turbo:frame-load', this.onFrameLoad)
  }

  disconnect() {
    document.removeEventListener('turbo:frame-load', this.onFrameLoad)
  }

  onFrameLoad(e) {
    const frame = e.target
    if (frame.id !== 'modal_frame') return

    const dialog = frame.querySelector('dialog')
    if (dialog && typeof dialog.showModal === 'function') {
      dialog.showModal()
      const closeBtn = dialog.querySelector('#closeModal')
      closeBtn?.addEventListener('click', () => dialog.close())
      const cancelBtn = dialog.querySelector('#cancelModal')
      cancelBtn?.addEventListener('click', () => dialog.close())
    }
  }

  // opcional: exponer acción para cerrar desde botones con data-action
  close(event) {
    const dialog = this.element.querySelector('dialog')
    dialog?.close()
  }
}
