import { Controller } from "@hotwired/stimulus"

// Builds a Table of Contents from the H2s inside .post-body, assigns
// slug IDs to each heading so the ToC links anchor cleanly, and tracks
// the currently visible H2 to highlight the matching ToC item.
export default class extends Controller {
  static targets = ["body", "list", "container"]

  connect() {
    const headings = this.bodyTarget.querySelectorAll("h2")
    if (!headings.length || headings.length < 2) {
      // No point showing a ToC for posts with <2 sections
      this.containerTarget.hidden = true
      return
    }

    const used = new Set()
    const items = []
    headings.forEach((h) => {
      let slug = this.slugify(h.textContent)
      if (used.has(slug)) slug = `${slug}-${used.size}`
      used.add(slug)
      h.id = slug
      items.push({ slug, text: h.textContent.trim() })
    })

    this.listTarget.innerHTML = items.map((it, idx) =>
      `<li><a href="#${it.slug}" data-toc-anchor="${it.slug}">${this.escapeHtml(it.text)}</a></li>`
    ).join("")

    this.containerTarget.hidden = false
    this.setupScrollSpy(headings)
  }

  setupScrollSpy(headings) {
    if (!("IntersectionObserver" in window)) return
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          this.listTarget.querySelectorAll("a").forEach(a => a.classList.remove("is-active"))
          const active = this.listTarget.querySelector(`[data-toc-anchor="${entry.target.id}"]`)
          if (active) active.classList.add("is-active")
        }
      })
    }, { rootMargin: "-80px 0px -65% 0px", threshold: 0 })

    headings.forEach(h => observer.observe(h))
    this._observer = observer
  }

  disconnect() {
    if (this._observer) this._observer.disconnect()
  }

  slugify(text) {
    return text.toString().toLowerCase()
      .normalize("NFD").replace(/[̀-ͯ]/g, "")
      .replace(/[^\w\s-]/g, "").trim()
      .replace(/\s+/g, "-")
      .replace(/-+/g, "-")
  }

  escapeHtml(s) {
    return String(s)
      .replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;").replaceAll("'", "&#39;")
  }
}
