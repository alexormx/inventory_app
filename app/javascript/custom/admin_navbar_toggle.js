// Admin navbar hamburger toggle (sin Bootstrap JS)
// Contrato:
//  - Botón: #admin-hamburger
//  - Contenedor colapsable: #admin-navbar (inicia oculto en mobile via CSS inline logic / clase helper)
//  - Añade/remueve clase 'is-open' y atributo hidden para accesibilidad.
//  - Sincroniza aria-expanded.
//  - Cierra al hacer click fuera, al navegar (turbo:before-render) y con Escape.
//  - Resistente a recargas Turbo múltiples.

(function(){
  const BTN_ID = 'admin-hamburger';
  const PANEL_ID = 'admin-navbar';
  const OPEN_CLASS = 'is-open';
  const SHOW_CLASS = 'show';
  const BTN_COLLAPSED = 'collapsed';

  function select(id){ return document.getElementById(id); }

  function applyInitialState(btn, panel){
    // En pantallas grandes dejar visible; en pequeñas ocultar inicialmente.
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
  }

  function open(btn, panel){
  panel.classList.add(OPEN_CLASS);
  panel.classList.add(SHOW_CLASS);
    panel.removeAttribute('hidden');
    btn.setAttribute('aria-expanded','true');
  btn.classList.remove(BTN_COLLAPSED);
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

    btn.addEventListener('click', (e)=>{
      e.preventDefault();
      toggle(btn, panel);
      e.stopPropagation();
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

    // Cerrar antes de navegación Turbo para evitar estados fantasma
    document.addEventListener('turbo:before-render', ()=>{
      if(panel.classList.contains(OPEN_CLASS)) close(btn, panel);
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
