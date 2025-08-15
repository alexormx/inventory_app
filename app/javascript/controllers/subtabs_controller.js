import { Controller } from "@hotwired/stimulus"

// Igual que tabs_controller, pero con identificador distinto para tabs anidados
// data-controller="subtabs"
// data-subtabs-target="tab|panel"
// data-action="click->subtabs#activate"
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = {
    activeClass: { type: String, default: "active show" },
    inactiveClass: { type: String, default: "" },
    defaultTab: String
  }

  connect() {
    const current = this.tabTargets.find(t => t.getAttribute("aria-selected") === "true" || t.classList.contains("active"))
    if (current) {
      this._showFor(current)
    } else {
      const byId = this.defaultTabValue && this.tabTargets.find(t => this._panelFor(t)?.id === this.defaultTabValue)
      this._showFor(byId || this.tabTargets[0])
    }
  }

  activate(event) {
    event.preventDefault()
    const btn = event.currentTarget
    this._showFor(btn)
  }

  _showFor(tabBtn) {
    if (!tabBtn) return

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
    const direct = tabBtn.dataset.target || tabBtn.getAttribute("data-target") || tabBtn.getAttribute("data-bs-target")
    const id = direct && direct.startsWith("#") ? direct.slice(1) : direct
    if (id) return this.panelTargets.find(p => p.id === id)
    const aria = tabBtn.getAttribute("aria-controls")
    if (aria) return this.panelTargets.find(p => p.id === aria)
    return null
  }
}
