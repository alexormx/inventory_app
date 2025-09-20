import { Controller } from "@hotwired/stimulus"

// Muestra la mejor coincidencia (sin dropdown) para Customer/Supplier al tipear
// Uso en el input de texto:
// <div data-controller="user-suggest" data-user-suggest-role-value="supplier">
//   <input type="text" data-user-suggest-target="input" />
//   <input type="hidden" name="purchase_order[user_id]" data-user-suggest-target="hidden" />
//   <div class="form-text" data-user-suggest-target="hint"></div>
// </div>
export default class extends Controller {
  static targets = ["input", "hint", "hidden", "results"]
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
  this._suggested = null
  this._activeIndex = -1
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
    if(!this.hasResultsTarget) return
    const items = Array.from(this.resultsTarget.querySelectorAll('[data-item]'))
    const max = items.length - 1
    if(event.key === 'ArrowDown'){
      event.preventDefault()
      this._activeIndex = Math.min(this._activeIndex + 1, max)
      this._highlight(items)
    } else if(event.key === 'ArrowUp'){
      event.preventDefault()
      this._activeIndex = Math.max(this._activeIndex - 1, 0)
      this._highlight(items)
    } else if(event.key === 'Enter' || event.key === 'Tab' || event.key === 'ArrowRight'){
      if(this._activeIndex >= 0 && items[this._activeIndex]){
        event.preventDefault()
        items[this._activeIndex].click()
      }
    } else if(event.key === 'Escape'){
      this._clearResults()
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
        if(Array.isArray(data) && data.length){
          this._renderList(data)
        } else {
          this._clearResults()
          this._renderInfo("Sin coincidencias")
        }
      })
      .catch(() => {
        this._clearResults()
        this._renderInfo("Error de búsqueda")
      })
  }

  _setSelection(user){
    if(this.hasHiddenTarget){
      this.hiddenTarget.value = user?.id || ""
    }
  }

  _renderList(users){
    if(!this.hasResultsTarget){ return }
    this.resultsTarget.innerHTML = ''
    const list = document.createElement('div')
    list.className = 'list-group position-absolute w-100 shadow-sm'
    users.forEach((u, idx) => {
      const a = document.createElement('button')
      a.type = 'button'
      a.className = 'list-group-item list-group-item-action'
      a.setAttribute('data-item', '1')
      a.textContent = u.name
      a.addEventListener('click', () => {
        this.inputTarget.value = u.name
        this._setSelection(u)
        this._clearResults()
        this._renderHint(`Seleccionado: <strong>${this._escapeHtml(u.name)}</strong>`)
      })
      list.appendChild(a)
    })
    this.resultsTarget.appendChild(list)
    this._activeIndex = 0
    this._highlight(Array.from(this.resultsTarget.querySelectorAll('[data-item]')))
  }

  _highlight(items){
    items.forEach((el, i) => {
      el.classList.toggle('active', i === this._activeIndex)
    })
  }

  _clearResults(){
    if(this.hasResultsTarget){
      this.resultsTarget.innerHTML = ''
    }
    this._activeIndex = -1
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
