import { Controller } from "@hotwired/stimulus"

// Autocomplete de ubicación por código o nombre
// Uso:
// <div data-controller="location-suggest" data-location-suggest-url-value="/admin/inventory_locations/search">
//   <input type="text" data-location-suggest-target="input" data-action="input->location-suggest#input keydown->location-suggest#keydown">
//   <input type="hidden" name="inventory_location_id" data-location-suggest-target="hidden">
//   <div data-location-suggest-target="results"></div>
//   <div data-location-suggest-target="hint" class="form-text"></div>
// </div>
export default class extends Controller {
  static targets = ["input", "hint", "hidden", "results"]
  static values = {
    url: { type: String, default: "/admin/inventory_locations/search" },
    minLength: { type: Number, default: 2 },
    debounceMs: { type: Number, default: 150 }
  }

  connect() {
    this._timer = null
    this._lastQuery = ""
    this._activeIndex = -1
    this._renderInfo("Escribe código o nombre de ubicación…")

    // Si ya viene un valor precargado
    if (this.hasHiddenTarget && this.hiddenTarget.value) {
      const name = this.hasInputTarget && this.inputTarget.value.trim().length
        ? this.inputTarget.value.trim()
        : null
      if (name) {
        this._renderHint(`<i class="fas fa-check-circle text-success"></i> Seleccionado: <strong>${this._escapeHtml(name)}</strong>`)
      }
    }

    // Cerrar resultados al hacer click fuera
    this._closeOnClickOutside = this._closeOnClickOutside.bind(this)
    document.addEventListener('click', this._closeOnClickOutside)
  }

  disconnect() {
    document.removeEventListener('click', this._closeOnClickOutside)
  }

  _closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this._clearResults()
    }
  }

  input() {
    const q = this.inputTarget.value.trim()
    if (q.length < this.minLengthValue) {
      this._setSelection(null)
      this._clearResults()
      this._renderInfo(`Escribe al menos ${this.minLengthValue} caracteres`)
      return
    }
    clearTimeout(this._timer)
    this._renderInfo("Buscando…")
    this._timer = setTimeout(() => this._search(q), this.debounceMsValue)
  }

  keydown(event) {
    if (!this.hasResultsTarget) return
    const items = Array.from(this.resultsTarget.querySelectorAll('[data-item]'))
    if (items.length === 0) return

    const max = items.length - 1

    if (event.key === 'ArrowDown') {
      event.preventDefault()
      this._activeIndex = Math.min(this._activeIndex + 1, max)
      this._highlight(items)
    } else if (event.key === 'ArrowUp') {
      event.preventDefault()
      this._activeIndex = Math.max(this._activeIndex - 1, 0)
      this._highlight(items)
    } else if (event.key === 'Enter') {
      event.preventDefault()
      if (this._activeIndex >= 0 && items[this._activeIndex]) {
        items[this._activeIndex].click()
      }
    } else if (event.key === 'Escape') {
      this._clearResults()
    }
  }

  _search(q) {
    this._lastQuery = q
    const url = new URL(this.urlValue, window.location.origin)
    url.searchParams.set('q', q)

    fetch(url.toString(), { headers: { 'Accept': 'application/json' } })
      .then(r => r.json())
      .then(data => {
        // Si el usuario ya cambió el texto, abortar render
        if (this._lastQuery !== this.inputTarget.value.trim()) return

        if (Array.isArray(data) && data.length) {
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

  _setSelection(location) {
    if (this.hasHiddenTarget) {
      this.hiddenTarget.value = location?.id || ""
    }
    // Disparar evento para que otros controladores puedan reaccionar
    if (location) {
      this.element.dispatchEvent(new CustomEvent('location-suggest:selected', {
        bubbles: true,
        detail: location
      }))
    }
  }

  _renderList(locations) {
    if (!this.hasResultsTarget) return

    this.resultsTarget.innerHTML = ''
    const list = document.createElement('div')
    list.className = 'list-group position-absolute w-100 shadow-sm location-suggest-dropdown'
    list.style.top = '100%'
    list.style.left = '0'
    list.style.zIndex = '1200'
    list.style.maxHeight = '300px'
    list.style.overflowY = 'auto'

    locations.forEach((loc, idx) => {
      const btn = document.createElement('button')
      btn.type = 'button'
      btn.className = 'list-group-item list-group-item-action py-2'
      btn.setAttribute('data-item', '1')
      btn.innerHTML = `
        <div class="d-flex justify-content-between align-items-start">
          <div>
            <code class="text-primary fw-bold">${this._escapeHtml(loc.code)}</code>
            <small class="text-muted ms-2">${this._escapeHtml(loc.type_name)}</small>
          </div>
        </div>
        <small class="text-muted">${this._escapeHtml(loc.full_path)}</small>
      `
      btn.addEventListener('click', () => {
        this.inputTarget.value = `${loc.code} - ${loc.full_path}`
        this._setSelection(loc)
        this._clearResults()
        this._renderHint(`<i class="fas fa-check-circle text-success"></i> <strong>${this._escapeHtml(loc.code)}</strong>: ${this._escapeHtml(loc.full_path)}`)
      })
      list.appendChild(btn)
    })

    this.resultsTarget.appendChild(list)
    this._activeIndex = 0
    this._highlight(Array.from(this.resultsTarget.querySelectorAll('[data-item]')))
  }

  _highlight(items) {
    items.forEach((el, i) => {
      el.classList.toggle('active', i === this._activeIndex)
    })
  }

  _clearResults() {
    if (this.hasResultsTarget) {
      this.resultsTarget.innerHTML = ''
    }
    this._activeIndex = -1
  }

  _renderInfo(text) {
    if (this.hasHintTarget) {
      this.hintTarget.innerHTML = `<span class="text-muted">${this._escapeHtml(text)}</span>`
    }
  }

  _renderHint(html) {
    if (this.hasHintTarget) {
      this.hintTarget.innerHTML = html
    }
  }

  _escapeHtml(str) {
    if (!str) return ''
    const div = document.createElement('div')
    div.textContent = str
    return div.innerHTML
  }

  // Método público para limpiar la selección
  clear() {
    if (this.hasInputTarget) this.inputTarget.value = ''
    if (this.hasHiddenTarget) this.hiddenTarget.value = ''
    this._clearResults()
    this._renderInfo("Escribe código o nombre de ubicación…")
  }
}
