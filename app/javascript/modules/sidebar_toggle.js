const DESKTOP_MEDIA_QUERY = "(min-width: 992px)"
const COLLAPSED_STORAGE_KEY = "sidebar-collapsed"
const SCROLL_STORAGE_KEY = "admin-sidebar-scroll-top"
const DRAWER_OPEN_CLASS = "is-open"
const BODY_OPEN_CLASS = "sidebar-drawer-open"
const desktopMedia = window.matchMedia(DESKTOP_MEDIA_QUERY)

let drawerOpener = null
let backdropFrame = null

function sidebar() {
  return document.getElementById("sidebar")
}

function adminContent() {
  return document.getElementById("admin-content")
}

function backdrop() {
  return document.getElementById("sidebar-backdrop")
}

function desktopToggle() {
  return document.querySelector("[data-sidebar-desktop-toggle]")
}

function drawerToggle() {
  return document.querySelector("[data-sidebar-drawer-toggle]")
}

function drawerCloseButton() {
  return document.querySelector("[data-sidebar-drawer-close]")
}

function storageGet(storage, key) {
  try {
    return storage.getItem(key)
  } catch (_error) {
    return null
  }
}

function storageSet(storage, key, value) {
  try {
    storage.setItem(key, value)
  } catch (_error) {
    // The sidebar still works when storage is unavailable.
  }
}

function isDesktop() {
  return desktopMedia.matches
}

function isDrawerOpen() {
  return sidebar()?.classList.contains(DRAWER_OPEN_CLASS) || false
}

function setInert(element, inert) {
  if (!element) return

  element.inert = inert
  if (inert) {
    element.setAttribute("inert", "")
  } else {
    element.removeAttribute("inert")
  }
}

function syncDesktopToggle() {
  const toggle = desktopToggle()
  if (!toggle) return

  const collapsed = document.documentElement.classList.contains("sidebar-collapsed")
  toggle.setAttribute("aria-expanded", String(!collapsed))
  toggle.setAttribute("aria-label", collapsed ? "Expandir navegación" : "Colapsar navegación")
}

function syncDrawerControls(open) {
  const openButton = drawerToggle()
  const closeButton = drawerCloseButton()

  if (openButton) {
    openButton.setAttribute("aria-expanded", String(open))
    openButton.setAttribute("aria-label", open ? "Cerrar navegación" : "Abrir navegación")
  }

  if (closeButton) {
    closeButton.setAttribute("aria-expanded", String(open))
    closeButton.setAttribute("aria-label", "Cerrar navegación")
  }
}

function setSidebarForDesktop() {
  const panel = sidebar()
  if (!panel) return

  panel.classList.remove(DRAWER_OPEN_CLASS)
  panel.removeAttribute("aria-hidden")
  panel.removeAttribute("aria-modal")
  panel.removeAttribute("role")
  setInert(panel, false)
  setInert(adminContent(), false)
  syncDrawerControls(false)
}

function setSidebarClosedOnMobile() {
  const panel = sidebar()
  if (!panel) return

  panel.classList.remove(DRAWER_OPEN_CLASS)
  panel.setAttribute("aria-hidden", "true")
  panel.removeAttribute("aria-modal")
  panel.removeAttribute("role")
  setInert(panel, true)
  setInert(adminContent(), false)
  syncDrawerControls(false)
}

function showBackdrop() {
  const overlay = backdrop()
  if (!overlay) return

  overlay.hidden = false
  if (backdropFrame) cancelAnimationFrame(backdropFrame)
  backdropFrame = requestAnimationFrame(() => {
    overlay.classList.add("is-visible")
    backdropFrame = null
  })
}

function hideBackdrop() {
  const overlay = backdrop()
  if (!overlay) return

  if (backdropFrame) {
    cancelAnimationFrame(backdropFrame)
    backdropFrame = null
  }
  overlay.classList.remove("is-visible")
  overlay.hidden = true
}

function openDrawer(opener) {
  const panel = sidebar()
  if (!panel || isDesktop() || isDrawerOpen()) return

  document.dispatchEvent(new CustomEvent("admin-navbar:close"))
  drawerOpener = opener || drawerToggle()
  panel.classList.add(DRAWER_OPEN_CLASS)
  panel.setAttribute("role", "dialog")
  panel.setAttribute("aria-modal", "true")
  panel.setAttribute("aria-hidden", "false")
  setInert(panel, false)
  setInert(adminContent(), true)
  document.body.classList.add(BODY_OPEN_CLASS)
  syncDrawerControls(true)
  showBackdrop()

  window.setTimeout(() => drawerCloseButton()?.focus(), 0)
}

function closeDrawer({ restoreFocus = true } = {}) {
  const panel = sidebar()
  const opener = drawerOpener

  if (panel) panel.classList.remove(DRAWER_OPEN_CLASS)
  document.body?.classList.remove(BODY_OPEN_CLASS)
  hideBackdrop()

  if (isDesktop()) {
    setSidebarForDesktop()
  } else {
    setSidebarClosedOnMobile()
  }

  drawerOpener = null
  if (restoreFocus && opener?.isConnected && !isDesktop()) {
    window.setTimeout(() => opener.focus(), 0)
  }
}

function toggleDesktopSidebar() {
  if (!isDesktop()) return

  const collapsed = document.documentElement.classList.toggle("sidebar-collapsed")
  storageSet(window.localStorage, COLLAPSED_STORAGE_KEY, String(collapsed))
  syncDesktopToggle()
}

function focusableDrawerElements() {
  const panel = sidebar()
  if (!panel) return []

  return Array.from(panel.querySelectorAll(
    'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])'
  )).filter((element) => element.getClientRects().length > 0 && !element.closest("[inert]"))
}

function trapDrawerFocus(event) {
  if (event.key !== "Tab" || !isDrawerOpen()) return

  const focusable = focusableDrawerElements()
  if (!focusable.length) {
    event.preventDefault()
    sidebar()?.focus()
    return
  }

  const first = focusable[0]
  const last = focusable[focusable.length - 1]
  const active = document.activeElement

  if (event.shiftKey && active === first) {
    event.preventDefault()
    last.focus()
  } else if (!event.shiftKey && active === last) {
    event.preventDefault()
    first.focus()
  }
}

function saveScrollPosition() {
  if (!isDesktop()) return

  const nav = document.querySelector("#sidebar .sidebar-nav")
  if (nav) storageSet(window.sessionStorage, SCROLL_STORAGE_KEY, String(nav.scrollTop))
}

function restoreScrollPosition() {
  const nav = document.querySelector("#sidebar .sidebar-nav")
  if (!nav) return

  if (!isDesktop()) {
    nav.scrollTop = 0
    return
  }

  const stored = Number.parseInt(storageGet(window.sessionStorage, SCROLL_STORAGE_KEY), 10)
  if (!Number.isFinite(stored)) return

  requestAnimationFrame(() => {
    nav.scrollTop = stored
  })
}

function initializeSidebar() {
  if (!sidebar()) {
    document.body?.classList.remove(BODY_OPEN_CLASS)
    document.documentElement.classList.remove("sidebar-collapsed")
    return
  }

  const collapsed = storageGet(window.localStorage, COLLAPSED_STORAGE_KEY) === "true"
  document.documentElement.classList.toggle("sidebar-collapsed", collapsed)
  closeDrawer({ restoreFocus: false })
  syncDesktopToggle()
  restoreScrollPosition()
}

function cleanupBeforeCache() {
  saveScrollPosition()
  closeDrawer({ restoreFocus: false })
}

document.addEventListener("click", (event) => {
  const target = event.target instanceof Element ? event.target : null
  if (!target) return

  const desktopButton = target.closest("[data-sidebar-desktop-toggle]")
  if (desktopButton) {
    event.preventDefault()
    toggleDesktopSidebar()
    return
  }

  const openButton = target.closest("[data-sidebar-drawer-toggle]")
  if (openButton) {
    event.preventDefault()
    isDrawerOpen() ? closeDrawer() : openDrawer(openButton)
    return
  }

  if (target.closest("[data-sidebar-drawer-close]") || target.closest("#sidebar-backdrop")) {
    event.preventDefault()
    closeDrawer()
    return
  }

  if (!isDesktop() && isDrawerOpen() && target.closest("#sidebar a[href]")) {
    closeDrawer({ restoreFocus: false })
  }
})

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && isDrawerOpen()) {
    event.preventDefault()
    closeDrawer()
    return
  }

  trapDrawerFocus(event)
})

document.addEventListener("admin-sidebar:close", () => closeDrawer({ restoreFocus: false }))
document.addEventListener("turbo:load", initializeSidebar)
document.addEventListener("turbo:before-cache", cleanupBeforeCache)
window.addEventListener("pagehide", cleanupBeforeCache)
desktopMedia.addEventListener("change", () => {
  closeDrawer({ restoreFocus: false })
  restoreScrollPosition()
})
