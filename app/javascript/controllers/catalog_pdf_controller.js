import { Controller } from "@hotwired/stimulus"

// Maneja la página de generación de catálogo (admin, solo local):
// - cambia la fuente de datos (API / BD local) y muestra/oculta los campos del API
// - carga las series de la fuente elegida
// - permite reordenar las series con drag & drop
// El orden del DOM define el orden en el PDF; los checkboxes marcados definen
// qué series se incluyen.
export default class extends Controller {
  static targets = ["source", "apiFields", "apiUrl", "apiToken", "status", "list", "rowTemplate",
                    "submitBtn", "progressCard", "progressBar", "progressLabel", "progressPercent", "progressError",
                    "usdEnabled", "usdRate"]
  static values = { seriesUrl: String, progressUrl: String, downloadUrl: String }

  connect() {
    this.dragged = null
    this.polling = null
    this.toggleApiFields()
    this.toggleUsd()
    this.reload()
  }

  // Habilita el campo de tipo de cambio solo cuando se pide el precio en USD.
  // Un input deshabilitado no se envía en el FormData, así que el rate solo
  // viaja cuando la opción está activa.
  toggleUsd() {
    const on = this.hasUsdEnabledTarget && this.usdEnabledTarget.checked
    if (this.hasUsdRateTarget) this.usdRateTarget.disabled = !on
  }

  disconnect() {
    if (this.polling) clearInterval(this.polling)
  }

  sourceChanged() {
    this.toggleApiFields()
    this.reload()
  }

  get source() {
    const checked = this.sourceTargets.find((r) => r.checked)
    return checked ? checked.value : "api"
  }

  toggleApiFields() {
    this.apiFieldsTarget.style.display = this.source === "api" ? "" : "none"
  }

  submit(event) {
    event.preventDefault()
    if (this.polling) clearInterval(this.polling)

    this.progressErrorTarget.classList.add("d-none")
    this.progressErrorTarget.textContent = ""
    this.progressCardTarget.classList.remove("d-none")
    this.submitBtnTarget.disabled = true
    this.setBar(0, "Iniciando…")

    fetch(this.element.action, {
      method: "POST",
      headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken() },
      body: new FormData(this.element)
    })
      .then((res) => res.json())
      .then((body) => {
        if (!body.job_id) throw new Error(body.error || "No se pudo iniciar la generación")
        this.poll(body.job_id)
      })
      .catch((err) => this.fail(err.message))
  }

  poll(jobId) {
    const url = new URL(this.progressUrlValue, window.location.origin)
    url.searchParams.set("job_id", jobId)

    this.polling = setInterval(() => {
      fetch(url, { headers: { Accept: "application/json" } })
        .then((res) => res.json())
        .then((state) => this.applyState(jobId, state))
        .catch((err) => this.fail(err.message))
    }, 700)
  }

  applyState(jobId, state) {
    if (state.status === "error") {
      this.fail(state.error || "Error al generar el catálogo")
      return
    }

    if (state.status === "rendering") {
      this.setBar(100, state.name || "Generando PDF…")
      return
    }

    if (state.status === "done") {
      clearInterval(this.polling)
      this.setBar(100, "Listo")
      this.submitBtnTarget.disabled = false
      const url = new URL(this.downloadUrlValue, window.location.origin)
      url.searchParams.set("job_id", jobId)
      window.open(url.toString(), "_blank")
      return
    }

    const total = state.total || 0
    const current = state.current || 0
    const pct = total > 0 ? Math.round((current / total) * 100) : 0
    const label = total > 0
      ? `Agregando ${current}/${total}: ${state.name}`
      : (state.name || "Cargando productos…")
    this.setBar(pct, label)
  }

  setBar(pct, label) {
    this.progressBarTarget.style.width = `${pct}%`
    this.progressPercentTarget.textContent = `${pct}%`
    this.progressLabelTarget.textContent = label
  }

  fail(message) {
    if (this.polling) clearInterval(this.polling)
    this.submitBtnTarget.disabled = false
    this.progressErrorTarget.textContent = message
    this.progressErrorTarget.classList.remove("d-none")
  }

  csrfToken() {
    const el = document.querySelector('meta[name="csrf-token"]')
    return el ? el.content : ""
  }

  reload() {
    const url = new URL(this.seriesUrlValue, window.location.origin)
    url.searchParams.set("source", this.source)
    if (this.source === "api") {
      if (this.hasApiUrlTarget && this.apiUrlTarget.value) url.searchParams.set("api_url", this.apiUrlTarget.value)
      if (this.hasApiTokenTarget && this.apiTokenTarget.value) url.searchParams.set("api_token", this.apiTokenTarget.value)
    }

    this.statusTarget.textContent = "Cargando series…"
    this.listTarget.innerHTML = ""

    fetch(url, { headers: { Accept: "application/json" } })
      .then((res) => res.json().then((body) => ({ ok: res.ok, body })))
      .then(({ ok, body }) => {
        if (!ok) throw new Error(body.error || "Error al cargar series")
        this.render(body.series || [])
      })
      .catch((err) => {
        this.statusTarget.textContent = err.message
      })
  }

  render(series) {
    if (series.length === 0) {
      this.statusTarget.textContent = "No hay series en esta fuente."
      return
    }
    this.statusTarget.textContent = `${series.length} serie(s)`

    series.forEach((serie) => {
      const row = this.rowTemplateTarget.content.firstElementChild.cloneNode(true)
      row.querySelector("input[type=checkbox]").value = serie.name
      row.querySelector("span").textContent = `${serie.name} (${serie.count})`
      this.attachDrag(row)
      this.listTarget.appendChild(row)
    })
  }

  attachDrag(row) {
    row.addEventListener("dragstart", () => {
      this.dragged = row
      row.classList.add("opacity-50")
    })
    row.addEventListener("dragend", () => {
      this.dragged = null
      row.classList.remove("opacity-50")
    })
    row.addEventListener("dragover", (event) => {
      event.preventDefault()
      if (!this.dragged || this.dragged === row) return
      const rect = row.getBoundingClientRect()
      const after = event.clientY > rect.top + rect.height / 2
      this.listTarget.insertBefore(this.dragged, after ? row.nextSibling : row)
    })
  }
}
