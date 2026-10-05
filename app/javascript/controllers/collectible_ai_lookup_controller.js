import { Controller } from "@hotwired/stimulus"

// Identificación con IA en quick_add. Sube la primera foto elegida, sondea el
// estado (JSON + intervalo, el patrón que ya funciona en la app) y, al terminar,
// llena SÓLO los campos vacíos y arma el panel. Todo texto de la IA entra con
// textContent: nunca innerHTML.
const RARITY = { comun: "Común", poco_comun: "Poco común", rara: "Rara", muy_rara: "Muy rara" }
const FIELDS = [
  ["product[product_name]", (r) => r.identification?.product_name, "Nombre"],
  ["product[brand]", (r) => r.identification?.brand, "Marca"],
  ["product[category]", (r) => r.suggested?.category, "Categoría"],
  ["product[description]", (r) => r.suggested?.description_es, "Descripción"],
]
const MAX_WAIT_MS = 4 * 60 * 1000

export default class extends Controller {
  static targets = ["fileInput", "button", "status", "panel"]
  static values = { createUrl: String, interval: { type: Number, default: 3000 } }

  disconnect() { this.stopPolling() }

  photoChanged() {
    if (!this.running) this.buttonTarget.disabled = !this.firstPhoto()
  }

  firstPhoto() { return this.fileInputTarget.files?.[0] }

  async start() {
    const photo = this.firstPhoto()
    if (!photo || this.running) return
    this.setRunning(true, "Buscando… (~30–60 s)")
    this.hidePanel()

    const body = new FormData()
    body.append("photo", photo)
    try {
      const res = await fetch(this.createUrlValue, {
        method: "POST",
        body,
        headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken() },
      })
      const json = await res.json().catch(() => ({}))
      if (!res.ok) return this.showError(json.error || "No se pudo iniciar la búsqueda.")
      this.poll(json.status_url)
    } catch (_e) {
      this.showError("No se pudo conectar con el servidor.")
    }
  }

  poll(url) {
    const startedAt = Date.now()
    this.stopPolling()
    this.timer = window.setInterval(async () => {
      if (Date.now() - startedAt > MAX_WAIT_MS) return this.showError("La búsqueda tardó demasiado. Intenta de nuevo.")
      try {
        const res = await fetch(url, { headers: { Accept: "application/json" } })
        const state = await res.json()
        if (state.status === "done") this.finish(state.result)
        else if (state.status === "failed") this.showError(state.error || "La búsqueda falló.")
      } catch (_e) { /* un tropiezo de red no termina la búsqueda; el tope de tiempo sí */ }
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.timer) window.clearInterval(this.timer)
    this.timer = null
  }

  finish(result) {
    this.stopPolling()
    this.setRunning(false, "Listo. Revisa los datos antes de guardar.")
    const suggestions = this.fillEmptyFields(result)
    this.renderPanel(result, suggestions)
  }

  fillEmptyFields(result) {
    const pending = []
    FIELDS.forEach(([name, pick, label]) => {
      const value = pick(result)
      const field = this.element.querySelector(`[name="${name}"]`)
      if (!value || !field) return
      if (field.value.trim() === "") field.value = value
      else if (field.value.trim() !== value) pending.push({ field, value, label })
    })
    return pending
  }

  renderPanel(r, suggestions) {
    const panel = this.panelTarget
    panel.replaceChildren()
    const header = this.el("div", "card-header bg-info-subtle fw-semibold", "Resultado de la IA")
    const body = this.el("div", "card-body small")
    panel.append(header, body)

    const id = r.identification || {}
    const conf = Math.round((id.confidence || 0) * 100)
    body.append(this.el("p", "mb-1", `${id.product_name || "Sin identificar"} · confianza ${conf}%`))
    if (conf < 60) body.append(this.el("div", "alert alert-warning py-1 mb-2", "Confianza baja: verifica el modelo."))
    const details = [id.brand, id.series, id.model_code, id.scale, id.year_or_edition].filter(Boolean).join(" · ")
    if (details) body.append(this.el("p", "text-muted mb-2", details))

    const launch = this.el("p", "mb-1", `Lanzamiento: ${r.launch_date?.value || "sin dato"}`)
    if (r.launch_date?.source_url) launch.append(" ", this.link(r.launch_date.source_url, "fuente"))
    body.append(launch)

    body.append(this.el("p", "mb-1", `Rareza: ${RARITY[r.rarity?.level] || "sin dato"}`))
    const reasons = this.el("ul", "mb-2")
    ;(r.rarity?.reasons || []).forEach((reason) => reasons.append(this.el("li", "", reason)))
    body.append(reasons)

    const row = this.el("div", "row g-3")
    row.append(this.market("🇲🇽 México", r.prices_mx, "MXN"), this.market("🌎 Mundial", r.prices_world, "USD"))
    body.append(row)

    suggestions.forEach(({ field, value, label }) => {
      const line = this.el("div", "d-flex align-items-start gap-2 mt-2")
      const button = this.el("button", "btn btn-sm btn-outline-primary", "Usar")
      button.type = "button"
      button.addEventListener("click", () => { field.value = value; line.remove() })
      line.append(button, this.el("span", "", `${label}: ${value}`))
      body.append(line)
    })

    if ((r.warnings || []).length) {
      const warn = this.el("ul", "text-warning-emphasis mt-2 mb-0")
      r.warnings.forEach((w) => warn.append(this.el("li", "", w)))
      body.append(warn)
    }
    panel.classList.remove("d-none")
  }

  market(title, data, currency) {
    const col = this.el("div", "col-12 col-md-6")
    col.append(this.el("div", "fw-semibold", title))
    if (!data) {
      col.append(this.el("div", "text-muted", "Sin datos en sitios confiables"))
      return col
    }
    col.append(this.el("div", "mb-1", `${currency} ${this.money(data.min)} – ${this.money(data.max)}`))
    const list = this.el("ul", "list-unstyled mb-0")
    data.listings.forEach((l) => {
      const item = this.el("li", "mb-1")
      item.append(this.link(l.url, l.title), ` · ${l.price_original} · ${l.sold ? "vendido" : "en venta"}`)
      list.append(item)
    })
    col.append(list)
    return col
  }

  showError(message) {
    this.stopPolling()
    this.setRunning(false, "")
    const panel = this.panelTarget
    panel.replaceChildren()
    const body = this.el("div", "card-body small d-flex align-items-center gap-2")
    const retry = this.el("button", "btn btn-sm btn-outline-danger", "Reintentar")
    retry.type = "button"
    retry.addEventListener("click", () => this.start())
    body.append(this.el("span", "text-danger", message), retry)
    panel.append(body)
    panel.classList.remove("d-none")
  }

  setRunning(running, text) {
    this.running = running
    this.buttonTarget.disabled = running || !this.firstPhoto()
    this.statusTarget.textContent = text
  }

  hidePanel() { this.panelTarget.classList.add("d-none") }

  money(n) { return `$${Number(n).toLocaleString("en-US", { minimumFractionDigits: n % 1 ? 2 : 0, maximumFractionDigits: 2 })}` }

  link(url, text) {
    const a = this.el("a", "", text)
    if (/^https?:\/\//.test(url)) a.href = url
    a.target = "_blank"
    a.rel = "noopener noreferrer"
    return a
  }

  el(tag, className, text) {
    const node = document.createElement(tag)
    if (className) node.className = className
    if (text !== undefined) node.textContent = text
    return node
  }

  csrfToken() { return document.querySelector('meta[name="csrf-token"]')?.content }
}
