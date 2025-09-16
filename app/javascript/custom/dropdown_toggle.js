document.addEventListener('turbo:load', initDropdowns)
document.addEventListener('DOMContentLoaded', initDropdowns)

function initDropdowns() {
  document.querySelectorAll('[data-dropdown-toggle]').forEach(btn => {
    if (btn.dataset.dropdownBound === 'true') return
    const menuId = btn.getAttribute('data-dropdown-menu')
    let menu = document.getElementById(menuId)
    if (!menu) {
      // Puede ocurrir al venir de admin (Turbo navigation) y el partial todavía no se ha reemplazado.
      // Reintentar una sola vez en el próximo frame.
      if (!btn.dataset.dropdownRetry) {
        btn.dataset.dropdownRetry = '1'
        requestAnimationFrame(()=> initDropdowns())
      }
      return
    }
    // Sólo marcar como bound cuando realmente encontramos el menú.
    btn.dataset.dropdownBound = 'true'

    // ARIA roles
    menu.setAttribute('role','menu')
    btn.setAttribute('role','button')
    btn.setAttribute('aria-haspopup','true')
    btn.setAttribute('aria-expanded','false')
    menu.querySelectorAll('a,button,[role="menuitem"]').forEach(item => {
      if(!item.getAttribute('role')) item.setAttribute('role','menuitem')
      item.setAttribute('tabindex','-1')
    })

    function open(){
      closeOthers(menu)
      menu.classList.add('show')
      btn.setAttribute('aria-expanded','true')
      // focus first item
      const first = menu.querySelector('[role="menuitem"]')
      first && setTimeout(()=> first.focus(), 0)
      document.addEventListener('keydown', onKey)
    }
    function close(focusBack=true){
      if(!menu.classList.contains('show')) return
      menu.classList.remove('show')
      btn.setAttribute('aria-expanded','false')
      document.removeEventListener('keydown', onKey)
      if(focusBack) setTimeout(()=> btn.focus(), 0)
    }
    function toggle(){ menu.classList.contains('show') ? close() : open() }

    function onKey(e){
      const items = Array.from(menu.querySelectorAll('[role="menuitem"]'))
      const currentIndex = items.indexOf(document.activeElement)
      switch(e.key){
        case 'Escape': close(); break
        case 'ArrowDown':
          e.preventDefault();
          if(!menu.classList.contains('show')) { open(); return }
          const next = items[(currentIndex+1) % items.length]; next && next.focus(); break
        case 'ArrowUp':
          e.preventDefault();
          if(!menu.classList.contains('show')) { open(); return }
          const prev = items[(currentIndex-1+items.length)%items.length]; prev && prev.focus(); break
        case 'Home':
          e.preventDefault(); items[0]?.focus(); break
        case 'End':
          e.preventDefault(); items[items.length-1]?.focus(); break
        case 'Tab':
          // Tab cierra y deja continuar navegación estándar
          close(false); break
        case 'Enter':
        case ' ': // Space
          if(document.activeElement && document.activeElement.getAttribute('role')==='menuitem'){
            document.activeElement.click();
          }
          break
      }
    }

  btn.addEventListener('click', e => { e.preventDefault(); toggle() })
    btn.addEventListener('keydown', e => {
      if(['ArrowDown','ArrowUp','Enter',' '].includes(e.key)){
        e.preventDefault(); toggle();
      }
    })

    // Cerrar con click fuera
    document.addEventListener('click', e => {
      if(btn.contains(e.target) || menu.contains(e.target)) return
      close(false)
    })

    // Cerrar al hacer click en un item que navega (enlaces o botones con data-turbo)
    menu.addEventListener('click', e => {
      const target = e.target.closest('[role="menuitem"]')
      if(!target) return
      // Si es un enlace normal dejar que Turbo navegue, pero cerrar primero
      close(false)
    })
  })

  // Cerrar todos si se hace scroll (evitar menús flotando fuera de contexto)
  window.addEventListener('scroll', () => {
    document.querySelectorAll('.dropdown-menu.show').forEach(m=>{
      const btn = document.querySelector('[data-dropdown-menu="'+m.id+'"]')
      m.classList.remove('show'); btn && btn.setAttribute('aria-expanded','false')
    })
  }, { passive:true })

  // Antes de navegar con Turbo cerrar cualquier dropdown abierto
  document.addEventListener('turbo:before-visit', () => {
    document.querySelectorAll('.dropdown-menu.show').forEach(m=>{
      m.classList.remove('show')
      const btn = document.querySelector('[data-dropdown-menu="'+m.id+'"]')
      btn && btn.setAttribute('aria-expanded','false')
    })
  })
}

// En caso de que turbo:load no alcance (navegaciones parciales), reforzar en turbo:render
document.addEventListener('turbo:render', () => { initDropdowns() })

// Fallback definitivo: observar inserciones del menú si el botón existe sin menú
const __dropdownObserver = new MutationObserver((mutations)=>{
  let needsInit=false
  for(const m of mutations){
    if([...m.addedNodes].some(n=> n.id && document.querySelector('[data-dropdown-toggle][data-dropdown-menu="'+n.id+'"]'))){
      needsInit=true; break
    }
  }
  if(needsInit) initDropdowns()
})
if(!window.__dropdownObserverStarted){
  window.__dropdownObserverStarted=true
  __dropdownObserver.observe(document.documentElement,{childList:true,subtree:true})
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
