// Alinea la flecha del preview bajo el icono del carrito. Sólo mide cuando el
// panel está abierto: antes medía en cada scroll y cada mouseover de la página.
(function () {
  const STATE = '__cartPreviewDyn'; if (window[STATE]) return; window[STATE] = true

  function align() {
    const link = document.querySelector('.site-navbar a[data-nav-link="cart"]')
    const panel = document.getElementById('cart-preview')
    if (!link || !panel || !panel.classList.contains('show')) return

    const linkRect = link.getBoundingClientRect()
    const panelRect = panel.getBoundingClientRect()
    const icon = link.querySelector('i')
    const iconRect = icon?.getBoundingClientRect()
    const iconCenter = iconRect ? iconRect.left + iconRect.width / 2 : linkRect.left + linkRect.width / 2
    const panelRight = panelRect.left + panelRect.width
    const offset = Math.min(Math.max(panelRight - iconCenter - 7, 12), panelRect.width - 24)
    panel.style.setProperty('--arrow-offset', offset + 'px')
  }

  document.addEventListener('cart-preview:shown', align)
  window.addEventListener('resize', align, { passive: true })
})()
