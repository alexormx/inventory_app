// app/javascript/controllers/kv_editor_controller.js
import { Controller } from "@hotwired/stimulus"

// A simple key/value editor that syncs to a hidden JSON field
export default class extends Controller {
  static targets = ["rows", "hidden"]
  static values = {
    initialValue: { type: Object, default: {} }
  }

  connect() {
    // Bootstrap rows from initialValue
    const entries = Object.entries(this.initialValueValue || {})
    if (entries.length === 0) {
      this.addRow()
    } else {
      entries.forEach(([k, v]) => this._appendRow(k, this._valueToString(v)))
    }
    this.sync()
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
        <button type="button" class="btn btn-outline-danger btn-sm" data-action="kv-editor#removeRow">&times;</button>
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
    let obj
    try {
      obj = JSON.parse(input)
    } catch (_e) {
      alert("JSON inválido")
      return
    }
    if (obj && typeof obj === "object" && !Array.isArray(obj)) {
      // limpiar filas actuales
      this.rowsTarget.innerHTML = ""
      Object.entries(obj).forEach(([k,v]) => this._appendRow(k, this._valueToString(v)))
      this.sync()
    } else {
      alert("Se esperaba un objeto JSON (clave/valor)")
    }
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
    } catch (_) {}

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
}
