import { Controller } from "@hotwired/stimulus"

// data-controller="tabs"
// data-tabs-active-class-value="active show"
// data-tabs-inactive-class-value=""
// data-tabs-target="tab" on button elements
// data-tabs-target="panel" on pane elements
// data-action="click->tabs#activate"
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = {
    activeClass: { type: String, default: "active show" },
    inactiveClass: { type: String, default: "" },
    defaultTab: String
  }

  connect() {
    // Si no hay un tab marcado como activo, activar el primero o el indicado por defaultTab
    const current = this.tabTargets.find(t => t.getAttribute("aria-selected") === "true" || t.classList.contains("active"))
    if (current) {
      this._showFor(current)
    } else {
      const byId = this.defaultTabValue && this.tabTargets.find(t => this._panelFor(t)?.id === this.defaultTabValue)
      this._showFor(byId || this.tabTargets[0])
    }

    // Sincronizar <select> móvil inicial si existe
    const select = this._selectEl()
    if (select) {
      const active = this.panelTargets.find(p => p.classList.contains('active')) || this.panelTargets[0]
      if (active) select.value = `#${active.id}`
    }
  }

  activate(event) {
    event.preventDefault()
    const btn = event.currentTarget
    this._showFor(btn)
  }

  // Modo móvil: <select> con opciones value="#pane-id"
  select(event) {
    const value = event.target.value
    if (!value) return
    const paneId = value.startsWith('#') ? value.slice(1) : value
    const pane = this.panelTargets.find(p => p.id === paneId)
    if (!pane) return
    // Buscar el tab asociado por aria-controls/target
    const tabBtn = this.tabTargets.find(t => {
      const direct = t.dataset.target || t.getAttribute('data-bs-target') || t.getAttribute('data-target')
      const id = direct && direct.startsWith('#') ? direct.slice(1) : direct
      const aria = t.getAttribute('aria-controls')
      return id === paneId || aria === paneId
    })
    this._showFor(tabBtn)
  }

  _showFor(tabBtn) {
    if (!tabBtn) return

    // Desactivar todos
    this.tabTargets.forEach(t => {
      t.classList.remove(...this.activeClassValue.split(" ").filter(Boolean))
      t.classList.add(...this.inactiveClassValue.split(" ").filter(Boolean))
      t.setAttribute("aria-selected", "false")
    })
    this.panelTargets.forEach(p => {
      p.classList.remove("active", "show")
      p.classList.add("fade")
      p.hidden = true
    })

    // Activar actual
    tabBtn.classList.add(...this.activeClassValue.split(" ").filter(Boolean))
    tabBtn.classList.remove(...this.inactiveClassValue.split(" ").filter(Boolean))
    tabBtn.setAttribute("aria-selected", "true")

    const panel = this._panelFor(tabBtn)
    if (panel) {
      panel.hidden = false
      panel.classList.add("active", "show")
      panel.classList.remove("fade")
    }
  }

  _panelFor(tabBtn) {
    // Busca por data-tabs-target-id o por data-target/hash tipo #pane-id
    const direct = tabBtn.dataset.target || tabBtn.getAttribute("data-bs-target") || tabBtn.getAttribute("data-target")
    const id = direct && direct.startsWith("#") ? direct.slice(1) : direct
    if (id) return this.panelTargets.find(p => p.id === id)

    // Fallback: usar aria-controls
    const aria = tabBtn.getAttribute("aria-controls")
    if (aria) return this.panelTargets.find(p => p.id === aria)

    return null
  }
}
