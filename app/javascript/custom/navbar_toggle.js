// Navbar público hamburger toggle (sin Bootstrap JS)
// Contrato:
//  - Botón: #hamburger
//  - Contenedor colapsable: #navbar-scroll (inicia oculto en mobile via CSS inline logic / clase helper)
//  - Añade/remueve clase 'is-open' y atributo hidden para accesibilidad.
//  - Sincroniza aria-expanded.
//  - Cierra al hacer click fuera, al navegar (turbo:before-render) y con Escape.
//  - Resistente a recargas Turbo múltiples.

(function(){
  const BTN_ID = 'hamburger';
  const PANEL_ID = 'navbar-scroll';
  const OPEN_CLASS = 'is-open';
  const SHOW_CLASS = 'show'; // Bootstrap collapse visible
  const BTN_COLLAPSED = 'collapsed';
  let backdropEl = null;

  function select(id){ return document.getElementById(id); }

  function applyInitialState(btn, panel){
    // En pantallas pequeñas ocultar inicialmente; en grandes mostrar.
    if(window.matchMedia('(max-width: 991.98px)').matches){
      if(!panel.classList.contains(OPEN_CLASS)){
        panel.setAttribute('hidden','');
        btn.setAttribute('aria-expanded','false');
        panel.classList.remove(SHOW_CLASS);
        btn.classList.add(BTN_COLLAPSED);
      }
    } else {
      panel.removeAttribute('hidden');
      btn.setAttribute('aria-expanded','true');
      panel.classList.add(SHOW_CLASS);
      btn.classList.remove(BTN_COLLAPSED);
    }
  }

  function close(btn, panel){
  panel.classList.remove(OPEN_CLASS);
  panel.classList.remove(SHOW_CLASS);
    panel.setAttribute('hidden','');
    btn.setAttribute('aria-expanded','false');
  btn.classList.add(BTN_COLLAPSED);
    btn.setAttribute('aria-label','Abrir menú');
    // Ocultar backdrop si existe
    if(backdropEl){
      backdropEl.classList.remove('show');
      backdropEl.setAttribute('hidden','');
      backdropEl.onclick = null;
    }
    // Limpiar stagger
    const items = panel.querySelectorAll('#navbar-menu > li');
    items.forEach(el => { el.style.transitionDelay=''; });
  }

  function ensureBackdrop(){
    if(backdropEl) return backdropEl;
    backdropEl = document.createElement('div');
    backdropEl.className = 'nav-backdrop';
    backdropEl.setAttribute('hidden','');
    document.body.appendChild(backdropEl);
    return backdropEl;
  }

  function positionBackdrop(){
    if(!backdropEl) return;
    const nav = document.querySelector('.site-navbar');
    const banner = document.getElementById('construction-banner');
    const bannerH = banner ? banner.offsetHeight : 0;
    const navH = nav ? nav.offsetHeight : 60;
    backdropEl.style.top = (bannerH + navH) + 'px';
  }

  function focusFirstItem(panel){
    const focusable = panel.querySelector(
      'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])'
    );
    focusable && setTimeout(()=> focusable.focus(), 0);
  }

  function open(btn, panel){
  panel.classList.add(OPEN_CLASS);
  panel.classList.add(SHOW_CLASS);
    panel.removeAttribute('hidden');
    btn.setAttribute('aria-expanded','true');
  btn.classList.remove(BTN_COLLAPSED);
    btn.setAttribute('aria-label','Cerrar menú');
    // Backdrop sólo en mobile
    if(window.matchMedia('(max-width: 991.98px)').matches){
      ensureBackdrop();
      positionBackdrop();
      backdropEl.removeAttribute('hidden');
      backdropEl.classList.add('show');
      backdropEl.onclick = () => close(btn, panel);
    }
    // Stagger de items del menú para efecto suave
    const items = panel.querySelectorAll('#navbar-menu > li');
    items.forEach((el, i) => { el.style.transitionDelay = (40*i)+'ms'; });
    focusFirstItem(panel);
  }

  function toggle(btn, panel){
    if(panel.classList.contains(OPEN_CLASS)){
      close(btn, panel);
    } else {
      open(btn, panel);
    }
  }

  function enhance(){
    const btn = select(BTN_ID);
    const panel = select(PANEL_ID);
    if(!btn || !panel) return;

    // Evitar múltiples bindings (Turbo re-visits)
    if(btn.dataset.enhanced === 'true') return;
    btn.dataset.enhanced = 'true';

    // Inicial
    applyInitialState(btn, panel);

    const onToggle = (e)=>{
      e.preventDefault();
      toggle(btn, panel);
      e.stopPropagation();
    };
    btn.addEventListener('click', onToggle);
    btn.addEventListener('keydown', (e)=>{
      if(e.key === 'Enter' || e.key === ' '){ onToggle(e); }
    });

    // Click fuera cierra
    document.addEventListener('click', (e)=>{
      if(!panel.contains(e.target) && !btn.contains(e.target)){
        if(panel.classList.contains(OPEN_CLASS)) close(btn, panel);
      }
    });

    // Escape cierra
  document.addEventListener('keydown', (e)=>{
      if(e.key === 'Escape' && panel.classList.contains(OPEN_CLASS)){
        close(btn, panel);
        btn.focus();
      }
    });

    // Al cambiar breakpoint (resize) re-evaluar
    const mql = window.matchMedia('(max-width: 991.98px)');
    mql.addEventListener('change', ()=> applyInitialState(btn, panel));
  window.addEventListener('resize', positionBackdrop, { passive:true });

    // Cerrar antes de navegación Turbo para evitar estados fantasma
    document.addEventListener('turbo:before-render', ()=>{
      if(panel.classList.contains(OPEN_CLASS)) close(btn, panel);
  if(backdropEl){ backdropEl.remove(); backdropEl=null; }
    });
  }

  // Inicialización en eventos Turbo y cuando idle (fallback)
  document.addEventListener('turbo:load', enhance);
  if('requestIdleCallback' in window){
    requestIdleCallback(()=>enhance(), { timeout:1500 });
  } else {
    window.setTimeout(enhance, 800);
  }
})();