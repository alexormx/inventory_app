import { Controller } from "@hotwired/stimulus"

// Referencia interactiva de la API (Swagger UI) dentro del admin.
// La librería pesa ~1 MB: se carga del CDN solo en esta página, una vez.
const VERSION = "5.17.14"
const BASE = `https://cdnjs.cloudflare.com/ajax/libs/swagger-ui/${VERSION}`

let loading = null

function loadSwaggerUi() {
  if (window.SwaggerUIBundle) return Promise.resolve(window.SwaggerUIBundle)
  if (loading) return loading

  const css = document.createElement("link")
  css.rel = "stylesheet"
  css.href = `${BASE}/swagger-ui.min.css`
  document.head.appendChild(css)

  loading = new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = `${BASE}/swagger-ui-bundle.min.js`
    script.onload = () => resolve(window.SwaggerUIBundle)
    script.onerror = () => { loading = null; reject(new Error("No se pudo cargar Swagger UI")) }
    document.head.appendChild(script)
  })
  return loading
}

export default class extends Controller {
  static values = { url: String }

  async connect() {
    try {
      const SwaggerUIBundle = await loadSwaggerUi()
      if (!this.element.isConnected) return

      this.element.innerHTML = ""
      SwaggerUIBundle({
        url: this.urlValue,
        domNode: this.element,
        presets: [SwaggerUIBundle.presets.apis],
        layout: "BaseLayout", // sin la barra superior de Swagger
        docExpansion: "list",
        defaultModelsExpandDepth: 0
      })
    } catch (error) {
      this.element.innerHTML = `<div class="alert alert-danger m-3">${error.message}. Revisa tu conexión y recarga.</div>`
    }
  }

  disconnect() {
    this.element.innerHTML = ""
  }
}
