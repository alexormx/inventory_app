import { Controller } from "@hotwired/stimulus"

// Manages the dynamic attribute schema rows in CategoryAttributeTemplate form
export default class extends Controller {
  static targets = ["container", "jsonField"]

  connect() {
    this.syncJson()
  }

  addRow() {
    const container = this.containerTarget
    const rows = container.querySelectorAll(".schema-row")
    const nextIndex = rows.length
    const nextPosition = nextIndex + 1

    const row = document.createElement("div")
    row.className = "row g-2 mb-2 align-items-center schema-row"
    row.dataset.index = nextIndex
    row.innerHTML = `
      <div class="col-md-2">
        <input type="text" class="form-control form-control-sm" placeholder="key" data-field="key" required>
      </div>
      <div class="col-md-2">
        <input type="text" class="form-control form-control-sm" placeholder="Label" data-field="label">
      </div>
      <div class="col-md-1">
        <select class="form-select form-select-sm" data-field="type">
          <option value="string">string</option>
          <option value="boolean">boolean</option>
          <option value="date">date</option>
        </select>
      </div>
      <div class="col-md-1 text-center">
        <div class="form-check d-inline-block">
          <input type="checkbox" class="form-check-input" data-field="required">
          <label class="form-check-label small">Req.</label>
        </div>
      </div>
      <div class="col-md-1">
        <input type="number" class="form-control form-control-sm" placeholder="#" value="${nextPosition}" data-field="position">
      </div>
      <div class="col-md-3">
        <input type="text" class="form-control form-control-sm" placeholder="Ejemplo..." data-field="example">
      </div>
      <div class="col-md-2 text-end">
        <button type="button" class="btn btn-outline-danger btn-sm" data-action="template-schema-editor#removeRow">
          <i class="fa fa-trash"></i>
        </button>
      </div>
    `
    container.appendChild(row)
    this.syncJson()

    // Focus the new key field
    row.querySelector('[data-field="key"]').focus()
  }

  removeRow(event) {
    const row = event.target.closest(".schema-row")
    if (row) {
      row.remove()
      this.syncJson()
    }
  }

  // Called before form submit to sync the visual rows into hidden JSON field
  syncJson() {
    const rows = this.containerTarget.querySelectorAll(".schema-row")
    const schema = []

    rows.forEach((row) => {
      const key = row.querySelector('[data-field="key"]')?.value?.trim()
      if (!key) return

      schema.push({
        key: key,
        label: row.querySelector('[data-field="label"]')?.value?.trim() || key,
        type: row.querySelector('[data-field="type"]')?.value || "string",
        required: row.querySelector('[data-field="required"]')?.checked || false,
        position: parseInt(row.querySelector('[data-field="position"]')?.value) || schema.length + 1,
        example: row.querySelector('[data-field="example"]')?.value?.trim() || ""
      })
    })

    this.jsonFieldTarget.value = JSON.stringify(schema)
  }

  // Observe input changes to keep JSON in sync
  containerTargetConnected() {
    this.containerTarget.addEventListener("input", () => this.syncJson())
    this.containerTarget.addEventListener("change", () => this.syncJson())
  }
}
