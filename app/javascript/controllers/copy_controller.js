import { Controller } from "@hotwired/stimulus"

// Copia un texto al portapapeles y muestra feedback breve ("¡Copiado!").
// Uso: data-controller="copy" data-copy-text-value="ABC123"
//      data-action="copy#copy" + data-copy-label-value (opcional)
export default class extends Controller {
  static values = {
    text: String,
    label: { type: String, default: "Copiado" },
    timeout: { type: Number, default: 1400 }
  }

  copy(event) {
    event.preventDefault()
    event.stopPropagation()

    const text = this.textValue
    if (!text) return

    const done = () => this.flash()
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done).catch(() => this.fallbackCopy(text, done))
    } else {
      this.fallbackCopy(text, done)
    }
  }

  fallbackCopy(text, done) {
    const ta = document.createElement("textarea")
    ta.value = text
    ta.setAttribute("readonly", "")
    ta.style.position = "absolute"
    ta.style.left = "-9999px"
    document.body.appendChild(ta)
    ta.select()
    try { document.execCommand("copy") } catch (_) {}
    document.body.removeChild(ta)
    done()
  }

  flash() {
    if (this._restoreTimer) clearTimeout(this._restoreTimer)
    if (this._original === undefined) this._original = this.element.innerHTML

    this.element.classList.add("is-copied")
    this.element.setAttribute("aria-label", `${this.labelValue}: ${this.textValue}`)
    this.element.innerHTML = `<i class="fas fa-check" aria-hidden="true"></i> ${this.labelValue}`

    this._restoreTimer = setTimeout(() => {
      this.element.classList.remove("is-copied")
      this.element.innerHTML = this._original
      this._original = undefined
    }, this.timeoutValue)
  }

  disconnect() {
    if (this._restoreTimer) clearTimeout(this._restoreTimer)
  }
}
