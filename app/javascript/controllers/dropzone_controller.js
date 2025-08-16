// app/javascript/controllers/dropzone_controller.js
import { Controller } from "@hotwired/stimulus"

// Minimal dropzone to enhance a hidden file input (multiple, direct upload)
// Targets:
// - input: the real file input
// - preview: container to list selected files (optional)
export default class extends Controller {
  static targets = ["input", "preview"]
  static values = {
    maxFiles: { type: Number, default: 10 },
    accept: { type: String, default: "image/*" }
  }

  connect() {
    // Debug: log targets if debugging enabled
    if (window.dropzoneDebug) {
      console.log('[dropzone] connect - hasInputTarget=', this.hasInputTarget, 'hasPreviewTarget=', this.hasPreviewTarget)
    }

    this.element.addEventListener("click", (e) => {
      // avoid clicking the remove buttons in preview
      if (e.target.closest("button[data-action]") || e.target.tagName === "BUTTON") return
      if (!this.inputTarget) {
        if (window.dropzoneDebug) console.warn('[dropzone] inputTarget not found')
        return
      }
      this.inputTarget.click()
    })

    this.element.addEventListener("dragover", (e) => {
      e.preventDefault(); this.element.classList.add("border-primary")
    })
    this.element.addEventListener("dragleave", () => {
      this.element.classList.remove("border-primary")
    })
    this.element.addEventListener("drop", (e) => {
      e.preventDefault()
      this.element.classList.remove("border-primary")
      if (!e.dataTransfer?.files?.length) return
      this._assignFiles(e.dataTransfer.files)
    })

    // reflect current input files if user selected previously
    this.inputTarget?.addEventListener("change", () => this.renderPreview())
    this.renderPreview()
  }

  _assignFiles(fileList) {
    const files = Array.from(fileList)
      .filter(f => this._accepts(f))
      .slice(0, this.maxFilesValue)
    // Build a new DataTransfer so we can assign programmatically
    const dt = new DataTransfer()
    files.forEach(f => dt.items.add(f))
    this.inputTarget.files = dt.files
    this.renderPreview()
  }

  _accepts(file) {
    if (!this.acceptValue || this.acceptValue === "*") return true
    const patterns = this.acceptValue.split(",").map(s => s.trim())
    return patterns.some(p => {
      if (p.endsWith("/*")) {
        const type = p.replace("/*", "")
        return file.type.startsWith(type)
      }
      return file.type === p || file.name.toLowerCase().endsWith(p.toLowerCase())
    })
  }

  removeFile(event) {
    event.preventDefault()
    const index = Number(event.currentTarget.dataset.index)
    const files = Array.from(this.inputTarget.files)
    files.splice(index, 1)
    const dt = new DataTransfer()
    files.forEach(f => dt.items.add(f))
    this.inputTarget.files = dt.files
    this.renderPreview()
  }

  renderPreview() {
    if (!this.hasPreviewTarget) return
    const files = Array.from(this.inputTarget?.files || [])
    this.previewTarget.innerHTML = ""
    files.forEach((f, idx) => {
      const li = document.createElement("li")
      li.className = "list-group-item d-flex justify-content-between align-items-center py-1"
      li.innerHTML = `
        <span class="text-truncate" style="max-width: 85%">${this._escape(f.name)} <small class="text-muted">(${Math.ceil(f.size/1024)} KB)</small></span>
        <button type="button" class="btn btn-sm btn-outline-danger" data-action="click->dropzone#removeFile" data-index="${idx}">×</button>
      `
      this.previewTarget.appendChild(li)
    })
  }

  _escape(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
