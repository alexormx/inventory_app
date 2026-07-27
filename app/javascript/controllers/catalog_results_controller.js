import { Controller } from "@hotwired/stimulus"

// Keeps one aria-live region stable outside the replaceable products frame.
// Clearing and restoring the message also announces completed updates whose
// result count did not change (for example, a sort change).
export default class extends Controller {
  connect() {
    this.frame = document.getElementById("products_grid")
    this.handleFrameRender = this.announce.bind(this)
    this.frame?.addEventListener("turbo:frame-render", this.handleFrameRender)
    this.announce()
  }

  disconnect() {
    this.frame?.removeEventListener("turbo:frame-render", this.handleFrameRender)
    if (this.announceFrame) cancelAnimationFrame(this.announceFrame)
  }

  announce(event) {
    const summary = this.frame?.querySelector("[data-results-announcement]")
    const message = summary?.dataset.resultsAnnouncement || ""
    const responseUrl = event?.detail?.fetchResponse?.response?.url

    this.syncSidebarSort(responseUrl || window.location.href)

    if (this.announceFrame) cancelAnimationFrame(this.announceFrame)
    this.element.textContent = ""
    this.announceFrame = requestAnimationFrame(() => {
      if (this.element.isConnected) this.element.textContent = message
    })
  }

  syncSidebarSort(href) {
    const sort = new URL(href, window.location.origin).searchParams.get("sort") || "newest"
    document.querySelectorAll('form.catalog-sidebar-filters input[name="sort"]').forEach((input) => {
      input.value = sort
    })
  }
}
