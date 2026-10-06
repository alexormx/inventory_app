import { Controller } from "@hotwired/stimulus"

// Identificación con IA en quick_add. Sube las fotos de los recuadros (cada una con su tipo) y las pistas, sondea
// el estado (JSON + intervalo, el patrón que ya funciona en la app) y, al
// terminar, llena SÓLO los campos vacíos y arma el panel. Si la IA no está
// segura no llena nada: enseña candidatos para que el admin elija. Todo texto
// de la IA o de Google entra con textContent: nunca innerHTML.
const RARITY = { comun: "Común", poco_comun: "Poco común", rara: "Rara", muy_rara: "Muy rara" }
const FIELDS = [
  ["product[product_name]", (r) => r.identification?.product_name, "Nombre"],
  ["product[brand]", (r) => r.identification?.brand, "Marca"],
  ["product[category]", (r) => r.suggested?.category, "Categoría"],
  ["product[description]", (r) => r.suggested?.description_es, "Descripción"],
]
const MAX_WAIT_MS = 4 * 60 * 1000
const MAX_PHOTOS = 5
const LOW_CONFIDENCE = 0.7

export default class extends Controller {
  static targets = ["slot", "button", "status", "panel", "actions", "hints", "lookupId"]
  static values = { createUrl: String, interval: { type: Number, default: 3000 } }

  disconnect() { this.stopPolling() }

  // Un recuadro por tipo de foto; la IA necesita al menos la vista 3/4.
  slotChanged(event) {
    this.renderSlot(event.target.closest("[data-collectible-ai-lookup-target='slot']"))
    this.refresh()
  }

  clearSlot(event) {
    const slot = event.target.closest("[data-collectible-ai-lookup-target='slot']")
    slot.querySelector("input[type='file']").value = ""
    this.renderSlot(slot)
    this.refresh()
  }

  renderSlot(slot) {
    const file = slot.querySelector("input[type='file']").files?.[0]
    const preview = slot.querySelector("[data-slot-preview]")
    if (preview.src.startsWith("blob:")) URL.revokeObjectURL(preview.src)
    if (file) preview.src = URL.createObjectURL(file)
    else preview.removeAttribute("src")
    preview.classList.toggle("d-none", !file)
    slot.querySelector("[data-slot-placeholder]").classList.toggle("d-none", Boolean(file))
    slot.querySelector("[data-slot-clear]").classList.toggle("d-none", !file)
  }

  // Fotos de los recuadros en su orden, cada una con su tipo.
  photos() {
    return this.slotTargets
      .map((slot) => ({ role: slot.dataset.role, file: slot.querySelector("input[type='file']").files?.[0] }))
      .filter((photo) => photo.file)
      .slice(0, MAX_PHOTOS)
  }

  hasRole(role) { return this.photos().some((photo) => photo.role === role) }

  refresh() {
    const any = this.photos().length > 0
    if (this.hasActionsTarget) this.actionsTarget.classList.toggle("d-none", !any && !this.running)
    if (this.running) return
    const ready = this.hasRole("three_quarter")
    this.buttonTarget.disabled = !ready
    if (!any) this.statusTarget.textContent = ""
    else if (!ready) this.statusTarget.textContent = "Agrega la vista 3/4 elevada para identificar con IA."
    else if (!this.hasRole("base")) this.statusTarget.textContent = "Agrega la foto de la base para que la IA lea el casting."
    else this.statusTarget.textContent = ""
  }

  async start() {
    const photos = this.photos()
    if (!this.hasRole("three_quarter") || this.running) return
    this.setRunning(true, "Buscando… (~30–90 s)")
    this.hidePanel()
    if (this.hasLookupIdTarget) this.lookupIdTarget.value = ""

    const body = new FormData()
    photos.forEach(({ role, file }) => {
      body.append("photos[]", file)
      body.append("photo_roles[]", role)
    })
    const hints = this.hasHintsTarget ? this.hintsTarget.value.trim() : ""
    if (hints) body.append("hints", hints)
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
        if (state.status === "done") this.finish(state.result, state.id)
        else if (state.status === "failed") this.showError(state.error || "La búsqueda falló.")
      } catch (_e) { /* un tropiezo de red no termina la búsqueda; el tope de tiempo sí */ }
    }, this.intervalValue)
  }

  stopPolling() {
    if (this.timer) window.clearInterval(this.timer)
    this.timer = null
  }

  finish(result, lookupId) {
    this.stopPolling()
    const confident = (result.identification?.confidence || 0) >= LOW_CONFIDENCE
    // Sólo una identificación confiable viaja con el alta: si la IA dudó, sus
    // datos (fecha, rareza) pueden ser de otro candidato.
    if (this.hasLookupIdTarget) this.lookupIdTarget.value = confident ? (lookupId ?? "") : ""
    this.setRunning(false, confident ? "Listo. Revisa los datos antes de guardar." : "La IA no está segura: elige la pieza correcta.")
    const suggestions = confident ? this.fillEmptyFields(result) : []
    this.renderPanel(result, suggestions, confident)
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

  renderPanel(r, suggestions, confident) {
    const panel = this.panelTarget
    panel.replaceChildren()
    const header = this.el("div", "card-header bg-info-subtle fw-semibold", "Resultado de la IA")
    const body = this.el("div", "card-body small")
    panel.append(header, body)

    const id = r.identification || {}
    const conf = Math.round((id.confidence || 0) * 100)
    body.append(this.el("p", "mb-1", `${id.product_name || "Sin identificar"} · confianza ${conf}%`))
    if (!confident) body.append(this.candidates(r))
    const details = [id.brand, id.series, id.model_code, id.scale, id.year_or_edition].filter(Boolean).join(" · ")
    if (details) body.append(this.el("p", "text-muted mb-2", details))
    const guesses = r.reverse_image?.best_guesses || []
    if (guesses.length) body.append(this.el("p", "text-muted mb-2", `Google sugiere: ${guesses.join(" · ")}`))

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

    this.appendSuggestions(body, suggestions)

    if ((r.warnings || []).length) {
      const warn = this.el("ul", "text-warning-emphasis mt-2 mb-0")
      r.warnings.forEach((w) => warn.append(this.el("li", "", w)))
      body.append(warn)
    }
    panel.classList.remove("d-none")
  }

  // Con confianza baja no se llena nada: el admin elige. La descripción y la
  // categoría se escribieron para el primer candidato; sólo se usan si es ése.
  candidates(r) {
    const box = this.el("div", "alert alert-warning py-2 mb-2")
    box.append(this.el("div", "fw-semibold mb-1", "No estoy seguro; elige la pieza correcta:"))
    const list = r.candidates?.length ? r.candidates : [{ ...r.identification, reason: "" }]
    list.forEach((c, index) => {
      const line = this.el("div", "d-flex align-items-start gap-2 mb-1")
      const pick = this.el("button", "btn btn-sm btn-outline-primary", "Es esta")
      pick.type = "button"
      pick.addEventListener("click", () => {
        const chosen = {
          identification: { product_name: c.product_name, brand: c.brand },
          suggested: index === 0 ? r.suggested : {},
        }
        box.querySelectorAll("button").forEach((b) => { b.disabled = true })
        this.appendSuggestions(box, this.fillEmptyFields(chosen))
        this.statusTarget.textContent = "Datos de la pieza elegida aplicados. Revisa antes de guardar."
      })
      const label = [c.product_name, c.brand, c.model_code].filter(Boolean).join(" · ")
      const pct = Math.round((c.confidence || 0) * 100)
      line.append(pick, this.el("span", "", `${label} (${pct}%)${c.reason ? ` — ${c.reason}` : ""}`))
      box.append(line)
    })
    return box
  }

  appendSuggestions(container, suggestions) {
    suggestions.forEach(({ field, value, label }) => {
      const line = this.el("div", "d-flex align-items-start gap-2 mt-2")
      const button = this.el("button", "btn btn-sm btn-outline-primary", "Usar")
      button.type = "button"
      button.addEventListener("click", () => { field.value = value; line.remove() })
      line.append(button, this.el("span", "", `${label}: ${value}`))
      container.append(line)
    })
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
    this.buttonTarget.disabled = running || !this.hasRole("three_quarter")
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
