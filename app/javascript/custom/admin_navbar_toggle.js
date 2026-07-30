// Controls only the compact actions menu in the admin navbar. The sidebar
// drawer and desktop collapse are owned by modules/sidebar_toggle.js.
const MOBILE_MEDIA_QUERY = "(max-width: 991.98px)"
const mobileMedia = window.matchMedia(MOBILE_MEDIA_QUERY)
const OPEN_CLASS = "is-open"
const SHOW_CLASS = "show"

let backdropElement = null
let backdropFrameId = null
let focusTimerId = null
let menuOpener = null

function button() {
  return document.getElementById("admin-hamburger")
}

function panel() {
  return document.getElementById("admin-navbar")
}

function isOpen() {
  return panel()?.classList.contains(OPEN_CLASS) || false
}

function ensureBackdrop() {
  if (backdropElement?.isConnected) return backdropElement

  backdropElement = document.createElement("div")
  backdropElement.className = "nav-backdrop"
  backdropElement.dataset.adminNavbarBackdrop = "true"
  backdropElement.hidden = true
  document.body.appendChild(backdropElement)
  return backdropElement
}

function syncButton(open) {
  const toggle = button()
  if (!toggle) return

  toggle.classList.toggle("collapsed", !open)
  toggle.setAttribute("aria-expanded", String(open))
  toggle.setAttribute("aria-label", open ? "Cerrar menú de acciones" : "Abrir menú de acciones")
}

function cancelDeferredWork() {
  if (backdropFrameId !== null) {
    window.cancelAnimationFrame(backdropFrameId)
    backdropFrameId = null
  }

  if (focusTimerId !== null) {
    window.clearTimeout(focusTimerId)
    focusTimerId = null
  }
}

function removeBackdrops() {
  document.querySelectorAll("[data-admin-navbar-backdrop]").forEach((backdrop) => backdrop.remove())
  backdropElement = null
}

function closeMenu({ restoreFocus = false } = {}) {
  const menu = panel()
  const opener = menuOpener

  cancelDeferredWork()

  if (menu) {
    menu.classList.remove(OPEN_CLASS, SHOW_CLASS)
    if (mobileMedia.matches) menu.hidden = true
    menu.querySelectorAll("li").forEach((item) => { item.style.transitionDelay = "" })
  }

  removeBackdrops()

  syncButton(false)
  menuOpener = null
  if (restoreFocus && opener?.isConnected) {
    focusTimerId = window.setTimeout(() => {
      focusTimerId = null
      if (opener.isConnected) opener.focus()
    }, 0)
  }
}

function cleanupNavbarState() {
  closeMenu()
}

function openMenu(opener) {
  const menu = panel()
  if (!menu || !mobileMedia.matches || isOpen()) return

  document.dispatchEvent(new CustomEvent("admin-sidebar:close"))
  menuOpener = opener || button()
  menu.hidden = false
  menu.classList.add(OPEN_CLASS, SHOW_CLASS)
  syncButton(true)

  const overlay = ensureBackdrop()
  const navbar = document.querySelector(".admin-navbar")
  overlay.style.top = `${navbar?.offsetHeight || 52}px`
  overlay.hidden = false
  backdropFrameId = window.requestAnimationFrame(() => {
    backdropFrameId = null
    if (overlay.isConnected && backdropElement === overlay && isOpen()) overlay.classList.add("show")
  })

  menu.querySelectorAll("li").forEach((item, index) => {
    item.style.transitionDelay = `${35 * index}ms`
  })
  focusTimerId = window.setTimeout(() => {
    focusTimerId = null
    if (menu.isConnected && isOpen()) menu.querySelector("a[href], button:not([disabled])")?.focus()
  }, 0)
}

function initializeMenu() {
  const menu = panel()

  cleanupNavbarState()
  if (!menu) return

  if (!mobileMedia.matches) {
    menu.hidden = false
    menu.classList.add(SHOW_CLASS)
    syncButton(true)
  }
}

function handleDocumentClick(event) {
  const target = event.target instanceof Element ? event.target : null
  if (!target) return

  const toggle = target.closest("#admin-hamburger")
  if (toggle) {
    event.preventDefault()
    event.stopPropagation()
    isOpen() ? closeMenu({ restoreFocus: true }) : openMenu(toggle)
    return
  }

  if (target.closest("[data-admin-navbar-backdrop]")) {
    closeMenu({ restoreFocus: true })
    return
  }

  const menu = panel()
  if (isOpen() && menu && !menu.contains(target)) closeMenu()
}

function handleDocumentKeydown(event) {
  if (event.key === "Escape" && isOpen()) {
    event.preventDefault()
    closeMenu({ restoreFocus: true })
  }
}

function handlePageShow() {
  initializeMenu()
}

document.addEventListener("click", handleDocumentClick)
document.addEventListener("keydown", handleDocumentKeydown)
document.addEventListener("admin-navbar:close", cleanupNavbarState)
document.addEventListener("turbo:load", initializeMenu)
document.addEventListener("turbo:before-cache", cleanupNavbarState)
window.addEventListener("pagehide", cleanupNavbarState)
window.addEventListener("pageshow", handlePageShow)
mobileMedia.addEventListener("change", initializeMenu)
