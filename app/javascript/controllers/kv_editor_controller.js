// app/javascript/controllers/kv_editor_controller.js
import { Controller } from "@hotwired/stimulus"

// A simple key/value editor that syncs to a hidden JSON field
export default class extends Controller {
  static targets = ["rows", "hidden"]
  static values = {
    initialValue: { type: Object, default: {} }
  }

  connect() {
    try {
      // Debug: report presence of targets if window.kvEditorDebug is set
      if (window.kvEditorDebug) {
        console.log('[kv-editor] connect start - hasRowsTarget=', this.hasRowsTarget, 'hasHiddenTarget=', this.hasHiddenTarget)
      }

      // Bootstrap rows from initialValue, con expansión automática si viene un "raw" con JSON-like
      let data = this.initialValueValue || {}
    const keys = Object.keys(data)
    if (keys.length === 1 && keys[0].toLowerCase() === "raw" && typeof data[keys[0]] === "string") {
      const expanded = this._tryParseLooseObject(data[keys[0]])
      if (expanded) data = expanded
    }

    const entries = Object.entries(data)
    if (entries.length === 0) this.addRow()
    else entries.forEach(([k, v]) => this._appendRow(k, this._valueToString(v)))
    this.sync()

    // Ensure we sync just before the form is submitted so the hidden field is current
    const form = this.element.closest('form')
    if (form) {
      form.addEventListener('submit', (ev) => this.sync())
    }
    if (window.kvEditorDebug) console.log('[kv-editor] connect end - rows now=', this.rowsTarget?.children?.length)
    } catch (err) {
      console.error('[kv-editor] connect error', err)
    }
  }

  addRow() {
    this._appendRow("", "")
  }

  removeRow(event) {
    event.preventDefault()
    const tr = event.currentTarget.closest("tr")
    tr?.remove()
    this.sync()
  }

  // Keep hidden JSON in sync when any input changes
  onInputChange() {
    this.sync()
  }

  sync() {
    const data = {}
    this.rowsTarget.querySelectorAll("tr").forEach(tr => {
      const key = tr.querySelector('input[name="kv_key[]"]').value.trim()
      const valStr = tr.querySelector('input[name="kv_val[]"]').value
      if (key.length === 0) return
      data[key.toLowerCase()] = this._stringToTypedValue(valStr)
    })
    this.hiddenTarget.value = JSON.stringify(data)
  }

  _appendRow(key, value) {
    const tr = document.createElement("tr")
    tr.innerHTML = `
      <td>
        <input type="text" name="kv_key[]" class="form-control form-control-sm" placeholder="key" value="${this._escape(key)}" />
      </td>
      <td>
        <input type="text" name="kv_val[]" class="form-control form-control-sm" placeholder="value" value="${this._escape(value)}" />
      </td>
      <td class="text-end">
        <div class="btn-group btn-group-sm">
          <button type="button" class="btn btn-outline-secondary" title="Expandir JSON" data-action="kv-editor#expandRow">⤢</button>
          <button type="button" class="btn btn-outline-danger" data-action="kv-editor#removeRow">&times;</button>
        </div>
      </td>
    `
    tr.querySelectorAll("input").forEach((input) => {
      input.addEventListener("input", () => this.onInputChange())
      input.addEventListener("change", () => this.onInputChange())
    })
    this.rowsTarget.appendChild(tr)
  }

  importJson(event) {
    event.preventDefault()
    const input = prompt("Pega JSON (objeto) para importar como filas:")
    if (!input) return
    const obj = this._tryParseLooseObject(input)
    if (obj) {
      // limpiar filas actuales
      this.rowsTarget.innerHTML = ""
      Object.entries(obj).forEach(([k,v]) => this._appendRow(k, this._valueToString(v)))
      this.sync()
    } else {
      alert("Se esperaba un objeto JSON (clave/valor)")
    }
  }

  expandRow(event) {
    event.preventDefault()
    const tr = event.currentTarget.closest("tr")
    const keyInput = tr.querySelector('input[name="kv_key[]"]')
    const valInput = tr.querySelector('input[name="kv_val[]"]')
    const obj = this._tryParseLooseObject(valInput.value)
    if (!obj) {
      alert("El valor no es un objeto JSON válido")
      return
    }
    // Reemplazar la fila por múltiples filas derivadas del objeto
    tr.remove()
    Object.entries(obj).forEach(([k, v]) => this._appendRow(k, this._valueToString(v)))
    this.sync()
  }

  _valueToString(v) {
    // Represent objects/arrays as JSON in the value input
    if (v === null || v === undefined) return ""
    if (typeof v === "object") return JSON.stringify(v)
    return String(v)
  }

  _stringToTypedValue(s) {
    const trimmed = (s ?? "").trim()
    if (trimmed === "") return null

    // Try JSON first (object/array/number/bool/null)
    try {
      return JSON.parse(trimmed)
    } catch (_) {
      // intentar con normalización laxa
      try {
        const normalized = this._normalizeLooseJson(trimmed)
        if (normalized !== trimmed) return JSON.parse(normalized)
      } catch (_) {}
    }

    // Fallbacks: booleans and numbers
    const lower = trimmed.toLowerCase()
    if (lower === "true") return true
    if (lower === "false") return false
    if (lower === "null") return null

    const num = Number(trimmed)
    if (!Number.isNaN(num) && /^-?\d+(\.\d+)?$/.test(trimmed)) return num

    // As plain string
    return trimmed
  }

  _escape(s) {
    return String(s).replace(/["&'<>]/g, (c) => {
      return ({ '"': '&quot;', "&": "&amp;", "'": "&#39;", "<": "&lt;", ">": "&gt;" })[c]
    })
  }

  // Helpers de parseo laxo (acepta Ruby-like con nil/=>/comillas simples)
  _tryParseLooseObject(input) {
    if (typeof input !== "string") return null
    const txt = input.trim()
    if (!this._looksLikeObject(txt)) return null
    // intento 1: JSON directo
    try {
      const parsed = JSON.parse(txt)
      return this._isPlainObject(parsed) ? parsed : null
    } catch (_) {}
    // intento 2: normalizado
    try {
      const normalized = this._normalizeLooseJson(txt)
      const parsed = JSON.parse(normalized)
      return this._isPlainObject(parsed) ? parsed : null
    } catch (_) {
      return null
    }
  }

  _normalizeLooseJson(s) {
    let t = s.trim()
    // reemplazar => por :
    t = t.replace(/=>/g, ":")
    // convertir comillas simples a dobles (aproximado)
    t = t.replace(/'/g, '"')
    // nil -> null
    t = t.replace(/\bnil\b/g, 'null')
    // símbolos :key => "key" (aproximado)
    t = t.replace(/:([a-zA-Z0-9_]+)/g, '"$1"')
    return t
  }

  _looksLikeObject(s) {
    return s.startsWith("{") && s.endsWith("}") && s.includes(":")
  }

  _isPlainObject(o) {
    return !!o && typeof o === 'object' && !Array.isArray(o)
  }
}

// Global fallback: allow adding a row from the console if Stimulus hasn't initialized
window.kvEditorAddRowFallback = function() {
  const rows = document.querySelector('[data-kv-editor-target="rows"]')
  if (!rows) return console.warn('kv-editor fallback: rows target not found')
  const tr = document.createElement('tr')
  tr.innerHTML = `
    <td>
      <input type="text" name="kv_key[]" class="form-control form-control-sm" placeholder="key" value="" />
    </td>
    <td>
      <input type="text" name="kv_val[]" class="form-control form-control-sm" placeholder="value" value="" />
    </td>
    <td class="text-end">
      <div class="btn-group btn-group-sm">
        <button type="button" class="btn btn-outline-secondary" title="Expandir JSON">⤢</button>
        <button type="button" class="btn btn-outline-danger">&times;</button>
      </div>
    </td>
  `
  rows.appendChild(tr)
}
