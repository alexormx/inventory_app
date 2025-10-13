import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["loading"]

  connect() {
    this.debounceTimer = null
    this.debounceDelay = 500 // 500ms debounce for inputs
    this.filtering = false
    this.showDelayTimer = null
    this.pendingRequests = 0

  // Sincronizar sidebar cuando se navega el frame (chips, limpiar todo, paginación, etc.)
  this.onFrameLinkClick = this.handleFrameLinkClick.bind(this)
  document.addEventListener('click', this.onFrameLinkClick)

    // Sincronizar el form de orden con los filtros actuales
    this.onSortChange = this.handleSortChange.bind(this)
    const headerForm = document.getElementById('header-sort-form')
    if (headerForm) {
      headerForm.addEventListener('change', this.onSortChange, true)
    }

    // Bind handlers to be able to remove later
  this.onBeforeFetch = this.showLoading.bind(this)
  this.onBeforeResponse = this.hideLoading.bind(this)
  this.onFrameLoad = this.hideLoading.bind(this)
  this.onFrameRender = this.onRendered.bind(this)

  // Nota: no usamos el listener global de before-fetch-request para evitar falsos positivos (prefetch/otros)
  // document.addEventListener('turbo:before-fetch-request', this.onBeforeFetch)
  document.addEventListener('turbo:before-fetch-response', this.onBeforeResponse)
    document.addEventListener('turbo:frame-load', this.onFrameLoad)
    document.addEventListener('turbo:frame-render', this.onFrameRender)

    // También escuchar directamente en el frame (por si el evento no burbujea en algunos entornos)
    this.bindFrameEvents()
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }
    document.removeEventListener('turbo:before-fetch-request', this.onBeforeFetch)
  document.removeEventListener('turbo:before-fetch-response', this.onBeforeResponse)
    document.removeEventListener('turbo:frame-load', this.onFrameLoad)
    document.removeEventListener('turbo:frame-render', this.onFrameRender)

    this.unbindFrameEvents()

    document.removeEventListener('click', this.onFrameLinkClick)
    const headerForm = document.getElementById('header-sort-form')
    if (headerForm) headerForm.removeEventListener('change', this.onSortChange, true)
  }

  showLoading(event) {
    const frame = document.getElementById('products_grid')
    if (!frame) return
    // Asegurar que el evento pertenece a nuestro frame (por robustez)
    if (event && event.target && event.target !== frame) return

    // Nueva solicitud del frame
    this.pendingRequests++

    // Capturar URL de la petición y sincronizar formularios lo antes posible
    try {
      const reqUrl = event && event.detail && event.detail.fetchOptions && event.detail.fetchOptions.url
      if (reqUrl) {
        this.applyUrlToForms(reqUrl)
      }
    } catch (_) {}

    // Solo mostrar el spinner cuando pasamos de 0 -> 1, con pequeño delay
    if (this.pendingRequests === 1) {
      if (this.showDelayTimer) clearTimeout(this.showDelayTimer)
      this.showDelayTimer = setTimeout(() => {
        frame.setAttribute('busy', '')
        frame.style.minHeight = frame.offsetHeight + 'px' // Prevent layout shift
      }, 120)
    }
  }

  hideLoading(event) {
    const frame = document.getElementById('products_grid')

    // Si el evento es la respuesta, decrementar el contador SOLO para nuestro frame
    if (event && event.type === 'turbo:before-fetch-response') {
      // Cuando se escucha a nivel documento, event.target debería ser el frame
      if (!event.target || event.target !== frame) {
        return
      }
      // Tomar la URL efectiva de la respuesta y sincronizar formularios
      try {
        const resp = event.detail && event.detail.fetchResponse && (event.detail.fetchResponse.response || event.detail.fetchResponse)
        const respUrl = resp && resp.url
        if (respUrl) {
          this.applyUrlToForms(respUrl)
        }
      } catch (_) {}
      this.pendingRequests = Math.max(0, this.pendingRequests - 1)
    }

    if (frame && this.pendingRequests === 0) {
      if (this.showDelayTimer) { clearTimeout(this.showDelayTimer); this.showDelayTimer = null }
      frame.removeAttribute('busy')
      setTimeout(() => {
        frame.style.minHeight = ''
      }, 300)
    }

    // Si el offcanvas móvil de filtros está abierto, ciérralo al terminar
    const offcanvas = document.querySelector('.offcanvas.show')
    if (offcanvas) {
      // Cierre compatible con nuestro polyfill
      offcanvas.classList.remove('show')
      offcanvas.setAttribute('aria-hidden', 'true')
      document.body.style.overflow = ''
      const bd = document.querySelector('[data-offcanvas-backdrop]')
      if (bd) { bd.classList.remove('show') }
    }
    // Resetear flag de filtrado si ya no hay solicitudes pendientes
    if (this.pendingRequests === 0) {
      this.filtering = false
    }
  }

  onRendered(event) {
    // Ocultar loading y re-enlazar al nuevo frame (por si fue reemplazado)
    // No decrementamos aquí; solo ocultamos si no hay pendientes
    this.hideLoading({})
    this.unbindFrameEvents()
    this.bindFrameEvents()
  }

  bindFrameEvents() {
    this.frameEl = document.getElementById('products_grid')
    if (!this.frameEl) return
    this._frameBeforeFetch = this.showLoading.bind(this)
    // En eventos de carga/render, no decrementamos; solo intentamos ocultar si pending == 0
    this._frameLoad = (e) => this.hideLoading({})
    this._frameRender = this.onRendered.bind(this)
    this.frameEl.addEventListener('turbo:before-fetch-request', this._frameBeforeFetch)
    this.frameEl.addEventListener('turbo:frame-load', this._frameLoad)
    this.frameEl.addEventListener('turbo:frame-render', this._frameRender)
  }

  unbindFrameEvents() {
    if (!this.frameEl) return
    if (this._frameBeforeFetch) this.frameEl.removeEventListener('turbo:before-fetch-request', this._frameBeforeFetch)
    if (this._frameLoad) this.frameEl.removeEventListener('turbo:frame-load', this._frameLoad)
    if (this._frameRender) this.frameEl.removeEventListener('turbo:frame-render', this._frameRender)
    this._frameBeforeFetch = null
    this._frameLoad = null
    this._frameRender = null
    this.frameEl = null
  }

  // Cuando se navega cualquier enlace dirigido al frame de productos, reflejar el nuevo estado en los formularios lateral/mobile
  handleFrameLinkClick(event) {
    const anchor = event.target && event.target.closest && event.target.closest('a[data-turbo-frame="products_grid"]')
    if (!anchor) return
    const href = anchor.getAttribute('href')
    if (!href) return
    // Aplicar los params del href a ambos formularios para que el UI coincida con el estado del frame
    this.applyUrlToForms(href)
  }

  applyUrlToForms(href) {
    let url
    try {
      url = new URL(href, window.location.origin)
    } catch (_) { return }
    const search = url.searchParams

    const forms = [
      document.getElementById('desktop-filters-form'),
      document.getElementById('mobile-filters-form')
    ].filter(Boolean)

    forms.forEach((form) => {
      // Categorías (array)
      const selectedCats = search.getAll('categories[]').concat(search.getAll('categories'))
      const catInputs = form.querySelectorAll('input[name="categories[]"][type="checkbox"]')
      catInputs.forEach((cb) => { cb.checked = selectedCats.includes(cb.value) })

      // Marcas (array)
      const selectedBrands = search.getAll('brands[]').concat(search.getAll('brands'))
      const brandInputs = form.querySelectorAll('input[name="brands[]"][type="checkbox"]')
      brandInputs.forEach((cb) => { cb.checked = selectedBrands.includes(cb.value) })

      // Precio
      const priceMin = search.get('price_min') || ''
      const priceMax = search.get('price_max') || ''
      const minInput = form.querySelector('input[name="price_min"]')
      const maxInput = form.querySelector('input[name="price_max"]')
      if (minInput) minInput.value = priceMin
      if (maxInput) maxInput.value = priceMax

      // Sincronizar el slider de precio si existe
      const priceRangeController = this.getPriceRangeController(form)
      if (priceRangeController) {
        priceRangeController.syncFromUrl(priceMin, priceMax)
      }

      // Disponibilidad
      const inStock = search.has('in_stock')
      const backorder = search.has('backorder')
      const preorder = search.has('preorder')
      const inStockInput = form.querySelector('input[name="in_stock"][type="checkbox"]')
      const backorderInput = form.querySelector('input[name="backorder"][type="checkbox"]')
      const preorderInput = form.querySelector('input[name="preorder"][type="checkbox"]')
      if (inStockInput) inStockInput.checked = inStock
      if (backorderInput) backorderInput.checked = backorder
      if (preorderInput) preorderInput.checked = preorder
    })

    // También reflejar los parámetros activos en el form de orden (cabecera)
    const headerForm = document.getElementById('header-sort-form')
    if (headerForm) {
      this.ensureHiddenInputs(headerForm, search)
    }
  }

  // Asegura inputs ocultos para los parámetros activos, para que al cambiar sort se mantengan los filtros
  ensureHiddenInputs(form, search) {
    // Primero limpiar previos ocultos dinámicos
    form.querySelectorAll('input[data-dynamic-hidden="1"]').forEach(el => el.remove())

    // Helper para crear input
    const addHidden = (name, value) => {
      const input = document.createElement('input')
      input.type = 'hidden'
      input.name = name
      input.value = value
      input.setAttribute('data-dynamic-hidden', '1')
      form.appendChild(input)
    }

    // Replicar q si existe
    const q = search.get('q')
    if (q) addHidden('q', q)

    // Replicar price_min/price_max
    const pmin = search.get('price_min')
    const pmax = search.get('price_max')
    if (pmin) addHidden('price_min', pmin)
    if (pmax) addHidden('price_max', pmax)

    // Replicar availability flags
    if (search.has('in_stock')) addHidden('in_stock', '1')
    if (search.has('backorder')) addHidden('backorder', '1')
    if (search.has('preorder')) addHidden('preorder', '1')

    // Replicar arrays categories[] y brands[] (admite ambas variantes)
    const cats = search.getAll('categories[]').concat(search.getAll('categories'))
    cats.forEach(v => addHidden('categories[]', v))
    const brands = search.getAll('brands[]').concat(search.getAll('brands'))
    brands.forEach(v => addHidden('brands[]', v))
  }

  // Cuando cambia el sort en el header, reconstruir la URL con filtros actuales y enviar al frame
  handleSortChange(event) {
    const form = (event && event.currentTarget && event.currentTarget.closest && event.currentTarget.closest('form'))
      || document.getElementById('header-sort-form')
    if (!form) return

    // Construir URL basada en el estado actual del sidebar (desktop si existe, sino mobile)
    const sourceForm = document.getElementById('desktop-filters-form') || document.getElementById('mobile-filters-form')
    const params = new URLSearchParams(new FormData(sourceForm || document.createElement('form')))

    // Inyectar sort actual
    const sortSelect = form.querySelector('select[name="sort"]')
    if (sortSelect && sortSelect.value) {
      params.set('sort', sortSelect.value)
    }

    // Mantener q si existe en el header form
    const qInput = form.querySelector('input[name="q"]')
    if (qInput && qInput.value) {
      params.set('q', qInput.value)
    }

    // Resetear paginación
    params.delete('page')

    // Navegar el frame con la URL resultante
  const basePath = (form.getAttribute('action') || window.location.pathname)
  const url = `${basePath}?${params.toString()}`
    const frame = document.getElementById('products_grid')
    if (frame) {
      frame.src = url
    } else {
      // fallback
      window.Turbo.visit(url, { frame: 'products_grid' })
    }
  }

  // Submit immediately for checkboxes and selects
  submit(event) {
    // Si el controlador está asociado al formulario de orden del header, manejar sort sin perder filtros
    if (this.element && this.element.id === 'header-sort-form') {
      if (event && typeof event.preventDefault === 'function') event.preventDefault()
      this.handleSortChange(event)
      return
    }
    // Don't auto-submit if it's a debounced input
    if (event.target.dataset.debounce === "true") {
      return
    }

    // Don't auto-submit on submit button click
    if (event.type === "submit" || event.target.type === "submit") {
      return
    }

    this.performSubmit()
  }

  // Debounced submit for text/number inputs
  debouncedSubmit(event) {
    if (event.target.dataset.debounce !== "true") {
      return
    }

    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    this.debounceTimer = setTimeout(() => {
      this.performSubmit()
    }, this.debounceDelay)
  }

  // Helper para obtener el controlador price-range de un formulario
  getPriceRangeController(form) {
    const sliderWrapper = form.querySelector('[data-controller~="price-range"]')
    if (!sliderWrapper) return null
    return this.application.getControllerForElementAndIdentifier(sliderWrapper, 'price-range')
  }

  performSubmit() {
    // Show loading indicator if we have one
    if (this.hasLoadingTarget) {
      this.loadingTarget.classList.remove("d-none")
    }

    // Submit the form
    this.filtering = true
    this.element.requestSubmit()
  }
}
