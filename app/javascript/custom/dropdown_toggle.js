document.addEventListener('turbo:load', initDropdowns)
document.addEventListener('DOMContentLoaded', initDropdowns)

function initDropdowns() {
  document.querySelectorAll('[data-dropdown-toggle]').forEach(btn => {
    if (btn.dataset.dropdownBound) return
    btn.dataset.dropdownBound = 'true'
    const menuId = btn.getAttribute('data-dropdown-menu')
    const menu = document.getElementById(menuId)
    if (!menu) return

    btn.addEventListener('click', e => {
      e.preventDefault()
      const isOpen = menu.classList.toggle('show')
      btn.setAttribute('aria-expanded', isOpen)
      if (isOpen) {
        closeOthers(menu)
      }
    })
  })

  document.addEventListener('click', e => {
    document.querySelectorAll('.dropdown-menu.show').forEach(openMenu => {
      const toggle = document.querySelector('[data-dropdown-menu="' + openMenu.id + '"]')
      if (toggle && (toggle === e.target || toggle.contains(e.target))) return
      if (!openMenu.contains(e.target)) {
        openMenu.classList.remove('show')
        const btn = document.querySelector('[data-dropdown-menu="' + openMenu.id + '"]')
        btn && btn.setAttribute('aria-expanded', 'false')
      }
    })
  })
}

function closeOthers(current) {
  document.querySelectorAll('.dropdown-menu.show').forEach(m => {
    if (m !== current) {
      m.classList.remove('show')
      const btn = document.querySelector('[data-dropdown-menu="' + m.id + '"]')
      btn && btn.setAttribute('aria-expanded', 'false')
    }
  })
}
