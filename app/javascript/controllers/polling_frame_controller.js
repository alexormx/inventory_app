import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    src: String,
    interval: { type: Number, default: 3000 },
    active: Boolean,
  }

  connect() {
    this.startIfNeeded()
  }

  disconnect() {
    this.stop()
  }

  activeValueChanged() {
    this.startIfNeeded()
  }

  startIfNeeded() {
    this.stop()
    if (!this.activeValue) return

    this.timer = window.setInterval(() => this.reload(), this.intervalValue)
  }

  stop() {
    if (!this.timer) return
    window.clearInterval(this.timer)
    this.timer = null
  }

  reload() {
    const base = this.srcValue || this.element.getAttribute("src")
    if (!base) return

    const separator = base.includes("?") ? "&" : "?"
    this.element.setAttribute("src", `${base}${separator}_poll=${Date.now()}`)
  }
}