// Mini preview del carrito: muestra panel al hover/foco sobre enlace del carrito.
(function () {
  const STATE = '__cartPreview'
  if (window[STATE]) return
  window[STATE] = true

  const MOBILE_QUERY = '(max-width: 991.98px)'
  const VIEWPORT_MARGIN = 8
  const MINIMUM_PANEL_HEIGHT = 320
  const AUTOHIDE_DELAY = 1500
  let currentLink = null
  let linkListenersInstalled = false
  let hideTimer = null
  let concealTimer = null

  function ready(callback) {
    if (document.readyState !== 'loading') callback()
    else document.addEventListener('DOMContentLoaded', callback, { once: true })
  }

  function currentPanel() {
    return document.getElementById('cart-preview')
  }

  function currentNavbar() {
    return document.querySelector('.site-navbar')
  }

  function usesMobilePreview() {
    return window.matchMedia(MOBILE_QUERY).matches
  }

  function updateScrollState() {
    const scrollBox = currentPanel()?.querySelector('.cart-preview-scroll')
    if (!scrollBox) return

    scrollBox.classList.toggle('has-top-fade', scrollBox.scrollTop > 2)
    scrollBox.classList.toggle('is-scrollable', scrollBox.scrollHeight > scrollBox.clientHeight + 8)
  }

  function clearOpenState(panel = currentPanel()) {
    currentNavbar()?.classList.remove('cart-preview-open')
    panel?.style.removeProperty('--cart-preview-viewport-top')
    currentLink?.setAttribute('aria-expanded', 'false')
  }

  function updatePreviewGeometry() {
    const panel = currentPanel()
    if (!panel) {
      clearOpenState()
      return
    }

    if (!usesMobilePreview()) {
      clearOpenState(panel)
      updateScrollState()
      return
    }

    currentNavbar()?.classList.add('cart-preview-open')
    const linkRect = currentLink?.getBoundingClientRect()
    const belowLinkTop = Math.max(VIEWPORT_MARGIN, (linkRect?.bottom || 0) + VIEWPORT_MARGIN)
    const minimumHeight = Math.min(MINIMUM_PANEL_HEIGHT, window.innerHeight - (VIEWPORT_MARGIN * 2))
    const availableBelowLink = window.innerHeight - belowLinkTop - VIEWPORT_MARGIN
    const top = availableBelowLink >= minimumHeight ? belowLinkTop : VIEWPORT_MARGIN

    panel.style.setProperty('--cart-preview-viewport-top', `${top}px`)
    updateScrollState()
  }

  function show() {
    const panel = currentPanel()
    if (!panel) return

    window.clearTimeout(hideTimer)
    window.clearTimeout(concealTimer)
    panel.hidden = false
    currentLink?.setAttribute('aria-expanded', 'true')
    if (usesMobilePreview()) currentNavbar()?.classList.add('cart-preview-open')

    requestAnimationFrame(() => {
      panel.classList.add('show')
      updatePreviewGeometry()
      requestAnimationFrame(updateScrollState)
    })
  }

  function conceal(panel) {
    if (panel && !panel.classList.contains('show')) panel.hidden = true
    clearOpenState(panel)
  }

  function hideImmediate({ restoreFocus = false, immediate = false } = {}) {
    const panel = currentPanel()
    window.clearTimeout(hideTimer)
    window.clearTimeout(concealTimer)

    if (!panel) {
      clearOpenState()
      return
    }

    delete panel.dataset.lockOpen
    panel.classList.remove('show')
    if (restoreFocus && panel.contains(document.activeElement)) currentLink?.focus()

    if (immediate) conceal(panel)
    else concealTimer = window.setTimeout(() => conceal(panel), 200)
  }

  function scheduleHide() {
    window.clearTimeout(hideTimer)
    hideTimer = window.setTimeout(() => {
      const panel = currentPanel()
      if (panel?.contains(document.activeElement)) return
      hideImmediate()
    }, AUTOHIDE_DELAY)
  }

  function unbindCurrentLink() {
    if (!currentLink?._cartPrevHandlers) return

    Object.entries(currentLink._cartPrevHandlers).forEach(([eventName, handler]) => {
      currentLink.removeEventListener(eventName, handler)
    })
    delete currentLink._cartPrevHandlers
  }

  function bindLink() {
    const link = document.querySelector('.site-navbar a[data-nav-link="cart"]')
    if (!link) return
    if (currentLink === link && linkListenersInstalled) return

    if (currentLink && currentLink !== link) unbindCurrentLink()

    const handlers = {
      mouseenter: () => {
        show()
        window.clearTimeout(hideTimer)
      },
      focus: () => {
        show()
        window.clearTimeout(hideTimer)
      },
      mouseleave: scheduleHide,
      blur: scheduleHide
    }
    Object.entries(handlers).forEach(([eventName, handler]) => link.addEventListener(eventName, handler))
    link._cartPrevHandlers = handlers
    link.setAttribute('aria-expanded', 'false')
    currentLink = link
    linkListenersInstalled = true
  }

  function bindPanelInteractions() {
    const panel = currentPanel()
    if (!panel || panel.__interactionsBound) return

    panel.addEventListener('mouseenter', () => {
      show()
      window.clearTimeout(hideTimer)
    })
    panel.addEventListener('mouseleave', scheduleHide)
    panel.addEventListener('focusin', () => {
      show()
      window.clearTimeout(hideTimer)
    })
    panel.addEventListener('focusout', (event) => {
      if (!panel.contains(event.relatedTarget)) scheduleHide()
    })
    panel.addEventListener('click', (event) => {
      if (event.target.closest('form')) show()
    })
    panel.addEventListener('submit', (event) => {
      if (event.target.closest('.cart-mini-qty-form') || event.target.matches('form[action*="/cart_items/"]')) show()
    })
    panel.__interactionsBound = true
  }

  function bindScrollState() {
    const scrollBox = currentPanel()?.querySelector('.cart-preview-scroll')
    if (!scrollBox || scrollBox.__fadeBound) return

    scrollBox.addEventListener('scroll', updateScrollState, { passive: true })
    scrollBox.__fadeBound = true
    updateScrollState()
  }

  function rebindAll() {
    bindLink()
    bindPanelInteractions()
    bindScrollState()
    const panel = currentPanel()

    if (panel?.dataset.lockOpen === 'true') {
      show()
      window.clearTimeout(panel._unlockTimer)
      panel._unlockTimer = window.setTimeout(() => { delete panel.dataset.lockOpen }, 5000)
    } else if (panel?.classList.contains('show')) {
      updatePreviewGeometry()
    } else {
      clearOpenState(panel)
    }
  }

  const observer = new MutationObserver((mutations) => {
    const previewAdded = mutations.some((mutation) => [...mutation.addedNodes].some((node) => (
      node.id === 'cart-preview' || node.querySelector?.('#cart-preview')
    )))
    if (previewAdded) rebindAll()
  })

  ready(() => {
    observer.observe(document.body, { childList: true, subtree: true })
    rebindAll()
  })

  document.addEventListener('turbo:render', rebindAll)
  document.addEventListener('turbo:before-render', () => hideImmediate({ immediate: true }))
  document.addEventListener('turbo:before-cache', () => {
    hideImmediate({ immediate: true })
    unbindCurrentLink()
    linkListenersInstalled = false
    currentLink = null
  })
  document.addEventListener('turbo:after-stream-render', () => {
    rebindAll()
    if (currentPanel()?.classList.contains('show')) updatePreviewGeometry()
  })

  document.addEventListener('click', (event) => {
    const panel = currentPanel()
    if (!panel) return

    if (event.target.closest('[data-cart-preview-close]')) {
      event.preventDefault()
      hideImmediate({ restoreFocus: true })
      return
    }
    if (panel.classList.contains('show') && !panel.contains(event.target) && !currentLink?.contains(event.target)) {
      hideImmediate()
    }
  }, true)

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape' && currentPanel()?.classList.contains('show')) {
      hideImmediate({ restoreFocus: true })
    }
  })

  window.addEventListener('resize', () => {
    const panel = currentPanel()
    if (!usesMobilePreview()) clearOpenState(panel)
    else if (panel?.classList.contains('show')) updatePreviewGeometry()
    updateScrollState()
  }, { passive: true })
})()
