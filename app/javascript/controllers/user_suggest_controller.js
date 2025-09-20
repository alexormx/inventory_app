import { Controller } from "@hotwired/stimulus"

// Muestra la mejor coincidencia (sin dropdown) para Customer/Supplier al tipear
// Uso en el input de texto:
// <div data-controller="user-suggest" data-user-suggest-role-value="supplier">
//   <input type="text" data-user-suggest-target="input" />
//   <input type="hidden" name="purchase_order[user_id]" data-user-suggest-target="hidden" />
//   <div class="form-text" data-user-suggest-target="hint"></div>
// </div>
export default class extends Controller {
  static targets = ["input", "hint", "hidden"]
  static values = {
    url: { type: String, default: "/admin/users/suggest" },
    role: { type: String, default: "" }, // "customer" | "supplier"
    minLength: { type: Number, default: 1 },
    debounceMs: { type: Number, default: 120 }
  }

  connect(){
    this._timer = null
    this._lastQuery = ""
    this._renderInfo("Escribe para buscar…")
  }

  input(){
    const q = this.inputTarget.value.trim()
    if(q.length < this.minLengthValue){
      this._setSelection(null)
      this._renderInfo(`Escribe al menos ${this.minLengthValue} caracter${this.minLengthValue>1?'es':''}.`)
      return
    }
    clearTimeout(this._timer)
    this._renderInfo("Buscando…")
    this._timer = setTimeout(() => this._suggest(q), this.debounceMsValue)
  }

  keydown(event){
    if((event.key === 'Tab' || event.key === 'ArrowRight' || event.key === 'Enter') && this._suggested){
      event.preventDefault()
      // Autocompletar texto al nombre sugerido
      this.inputTarget.value = this._suggested.name
      this._setSelection(this._suggested)
    }
  }

  _suggest(q){
    this._lastQuery = q
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set('q', q)
    if(this.roleValue) url.searchParams.set('role', this.roleValue)
    fetch(url.toString(), { headers: { 'Accept': 'application/json' }})
      .then(r => r.json())
      .then(data => {
        // Si el usuario ya cambió el texto, abortar render
        if(this._lastQuery !== this.inputTarget.value.trim()) return
        if(data && data.id){
          this._suggested = data
          this._setSelection(data)
          this._renderHint(`Coincidencia: <strong>${this._escapeHtml(data.name)}</strong>`) 
        } else {
          this._suggested = null
          this._setSelection(null)
          this._renderInfo("Sin coincidencias")
        }
      })
      .catch(() => {
        this._suggested = null
        this._setSelection(null)
        this._renderInfo("Error de búsqueda")
      })
  }

  _setSelection(user){
    if(this.hasHiddenTarget){
      this.hiddenTarget.value = user?.id || ""
    }
  }

  _renderInfo(text){
    if(this.hasHintTarget){
      this.hintTarget.innerHTML = `<span class="text-muted">${this._escapeHtml(text)}</span>`
    }
  }

  _renderHint(html){
    if(this.hasHintTarget){
      this.hintTarget.innerHTML = html
    }
  }

  _escapeHtml(str){
    return String(str).replace(/[&<>"]/g, s => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[s]))
  }
}
