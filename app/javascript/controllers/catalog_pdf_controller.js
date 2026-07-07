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
                    "usdEnabled", "usdRate", "title", "sort", "direction",
                    "fmtPortrait", "fmtLandscape", "fmtImages"]
  static values = { seriesUrl: String, progressUrl: String, downloadUrl: String }

  connect() {
    this.dragged = null
    this.polling = null
    this.restoreOptions()
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

    if (!this.anyFormatSelected()) {
      this.fail("Selecciona al menos un formato (PDF vertical, horizontal o imágenes).")
      return
    }

    if (this.polling) clearInterval(this.polling)
    this.finished = false
    this.inFlight = false

    this.saveOrder()
    this.saveOptions()
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
      // Evita solapar peticiones: si la anterior sigue en vuelo, espera al
      // próximo tick. Así no se acumulan respuestas "done" que abrirían el PDF
      // varias veces.
      if (this.inFlight) return
      this.inFlight = true
      fetch(url, { headers: { Accept: "application/json" } })
        .then((res) => res.json())
        .then((state) => this.applyState(jobId, state))
        .catch((err) => this.fail(err.message))
        .finally(() => { this.inFlight = false })
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
      if (this.finished) return
      this.finished = true
      clearInterval(this.polling)
      this.polling = null
      this.setBar(100, "Listo")
      this.submitBtnTarget.disabled = false
      this.downloadResult(jobId, state)
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

  // Dispara la descarga sin window.open: como el "done" llega desde el polling
  // (no un gesto del usuario), abrir una pestaña para un archivo con
  // Content-Disposition: attachment (el ZIP de imágenes) hace que el navegador
  // cancele la descarga. Un <a> temporal descarga en la misma página; el PDF
  // (inline) sí se abre en pestaña nueva para verlo.
  downloadResult(jobId, state) {
    const url = new URL(this.downloadUrlValue, window.location.origin)
    url.searchParams.set("job_id", jobId)

    const link = document.createElement("a")
    link.href = url.toString()
    if (state.content_type === "application/pdf") {
      link.target = "_blank"
      link.rel = "noopener"
    } else {
      link.download = state.filename || "catalogo.zip"
    }
    document.body.appendChild(link)
    link.click()
    link.remove()
  }

  setBar(pct, label) {
    this.progressBarTarget.style.width = `${pct}%`
    this.progressPercentTarget.textContent = `${pct}%`
    this.progressLabelTarget.textContent = label
  }

  fail(message) {
    if (this.polling) clearInterval(this.polling)
    this.submitBtnTarget.disabled = false
    this.progressCardTarget.classList.remove("d-none")
    this.progressErrorTarget.textContent = message
    this.progressErrorTarget.classList.remove("d-none")
  }

  anyFormatSelected() {
    return (this.hasFmtPortraitTarget && this.fmtPortraitTarget.checked) ||
           (this.hasFmtLandscapeTarget && this.fmtLandscapeTarget.checked) ||
           (this.hasFmtImagesTarget && this.fmtImagesTarget.checked)
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

    this.applySavedOrder(series).forEach((serie) => {
      const row = this.rowTemplateTarget.content.firstElementChild.cloneNode(true)
      row.querySelector("input[type=checkbox]").value = serie.name
      row.querySelector("span").textContent = `${serie.name} (${serie.count})`
      this.attachDrag(row)
      this.listTarget.appendChild(row)
    })
  }

  // --- Persistencia del orden de series (localStorage) ---------------------
  // El generador corre solo en local y lo usa una sola persona, así que el
  // orden preferido se guarda en el navegador. Las series guardadas salen
  // primero (en su orden); las nuevas (no guardadas aún) van al final
  // conservando el orden alfabético que manda el servidor.
  get storageKey() {
    return "catalogPdfSeriesOrder"
  }

  loadOrder() {
    try {
      const raw = window.localStorage.getItem(this.storageKey)
      return raw ? JSON.parse(raw) : []
    } catch (e) {
      return []
    }
  }

  saveOrder() {
    const names = Array.from(this.listTarget.querySelectorAll("input[type=checkbox]")).map((cb) => cb.value)
    if (names.length === 0) return
    try {
      window.localStorage.setItem(this.storageKey, JSON.stringify(names))
    } catch (e) {
      // localStorage no disponible (modo privado, etc.): seguir sin persistir
    }
  }

  applySavedOrder(series) {
    const saved = this.loadOrder()
    if (saved.length === 0) return series
    const rank = new Map(saved.map((name, i) => [name, i]))
    // Array.sort es estable: los empates (ambos sin guardar) conservan el
    // orden de entrada.
    return [...series].sort((a, b) => {
      const ra = rank.has(a.name) ? rank.get(a.name) : Infinity
      const rb = rank.has(b.name) ? rank.get(b.name) : Infinity
      return ra - rb
    })
  }

  // --- Persistencia de las opciones del catálogo (localStorage) ------------
  // Mismo enfoque que el orden de series: el generador corre solo en local y lo
  // usa una persona, así que las opciones (título, orden, dirección, USD y tipo
  // de cambio) se recuerdan en el navegador para el próximo catálogo.
  get optionsKey() {
    return "catalogPdfOptions"
  }

  loadOptions() {
    try {
      const raw = window.localStorage.getItem(this.optionsKey)
      return raw ? JSON.parse(raw) : {}
    } catch (e) {
      return {}
    }
  }

  saveOptions() {
    const opts = {
      title: this.hasTitleTarget ? this.titleTarget.value : "",
      sort: this.hasSortTarget ? this.sortTarget.value : "",
      direction: this.hasDirectionTarget ? this.directionTarget.value : "",
      includeUsd: this.hasUsdEnabledTarget ? this.usdEnabledTarget.checked : false,
      usdRate: this.hasUsdRateTarget ? this.usdRateTarget.value : "",
      fmtPortrait: this.hasFmtPortraitTarget ? this.fmtPortraitTarget.checked : true,
      fmtLandscape: this.hasFmtLandscapeTarget ? this.fmtLandscapeTarget.checked : false,
      fmtImages: this.hasFmtImagesTarget ? this.fmtImagesTarget.checked : false
    }
    try {
      window.localStorage.setItem(this.optionsKey, JSON.stringify(opts))
    } catch (e) {
      // localStorage no disponible: seguir sin persistir
    }
  }

  restoreOptions() {
    const opts = this.loadOptions()
    if (this.hasTitleTarget && opts.title != null) this.titleTarget.value = opts.title
    if (this.hasSortTarget && opts.sort) this.sortTarget.value = opts.sort
    if (this.hasDirectionTarget && opts.direction) this.directionTarget.value = opts.direction
    if (this.hasUsdEnabledTarget && opts.includeUsd != null) this.usdEnabledTarget.checked = !!opts.includeUsd
    if (this.hasUsdRateTarget && opts.usdRate != null) this.usdRateTarget.value = opts.usdRate
    if (this.hasFmtPortraitTarget && opts.fmtPortrait != null) this.fmtPortraitTarget.checked = !!opts.fmtPortrait
    if (this.hasFmtLandscapeTarget && opts.fmtLandscape != null) this.fmtLandscapeTarget.checked = !!opts.fmtLandscape
    if (this.hasFmtImagesTarget && opts.fmtImages != null) this.fmtImagesTarget.checked = !!opts.fmtImages
  }

  attachDrag(row) {
    row.addEventListener("dragstart", () => {
      this.dragged = row
      row.classList.add("opacity-50")
    })
    row.addEventListener("dragend", () => {
      this.dragged = null
      row.classList.remove("opacity-50")
      this.saveOrder()
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
