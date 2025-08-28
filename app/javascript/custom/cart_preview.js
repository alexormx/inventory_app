// Mini preview del carrito: muestra panel al hover/foco sobre enlace del carrito
(function(){
  const STATE='__cartPreview'; if(window[STATE]) return; window[STATE]=true;
  function ready(fn){ if(document.readyState!=='loading') fn(); else document.addEventListener('turbo:load', fn); }

  let currentLink=null;
  let hideTimer=null;
  let linkListenersInstalled=false;

  function currentPanel(){ return document.getElementById('cart-preview'); }

  function show(){
    const panel=currentPanel(); if(!panel) return;
    clearTimeout(hideTimer);
    panel.hidden=false;
    requestAnimationFrame(()=> panel.classList.add('show'));
  }
  function scheduleHide(ev){
    const panel=currentPanel(); if(!panel) return;
    const link=currentLink;
    const toEl = ev && (ev.relatedTarget || ev.toElement);
    if(toEl && (panel.contains(toEl) || (link && link.contains(toEl)))) return; // movimiento interno
    if(panel.matches(':hover') || panel.contains(document.activeElement) || panel.dataset.lockOpen==='true') return;
    clearTimeout(hideTimer);
    hideTimer = setTimeout(()=>{
      if(panel.dataset.lockOpen==='true') return; // se volvió a bloquear
      panel.classList.remove('show');
      setTimeout(()=>{ const p=currentPanel(); if(p && !p.classList.contains('show')) p.hidden=true; },220);
    },320);
  }

  function bindLink(){
    const link=document.querySelector('.site-navbar a[href*="/cart"]');
    if(!link) return;
    if(currentLink === link && linkListenersInstalled) return;
    // Si hubo link previo diferente, remover listeners previos
    if(currentLink && currentLink !== link){
      ['mouseenter','focus','mouseleave','blur'].forEach(ev=> currentLink.removeEventListener(ev, link._cartPrevHandlers?.[ev]));
    }
    // Preparar handlers y adjuntar
    const handlers={};
    handlers['mouseenter']=show;
    handlers['focus']=show;
  handlers['mouseleave']=scheduleHide;
    handlers['blur']=scheduleHide;
    ['mouseenter','focus','mouseleave','blur'].forEach(ev=> link.addEventListener(ev, handlers[ev]));
    link._cartPrevHandlers=handlers; // guardar en nodo para remover futuro
    currentLink=link;
    linkListenersInstalled=true;
  }

  function bindPanelHover(){
    const panel=currentPanel(); if(!panel) return;
    if(panel.__hoverBound){
      // no rebind necesario, ya está
      return;
    }
    panel.addEventListener('mouseenter', show);
    panel.addEventListener('mouseleave', scheduleHide);
    panel.__hoverBound=true;
    // Evitar cierre al hacer click en botones internos
    panel.addEventListener('click', (e)=>{
      if(e.target.closest('form')){
          panel.dataset.lockOpen='true';
          show();
      }
    });
    // Interceptar submits internos para mantener abierto tras respuesta
    panel.addEventListener('submit', (e)=>{
      if(e.target.closest('.cart-mini-qty-form') || e.target.matches('form[action*="/cart_items/"]')){
          panel.dataset.lockOpen='true';
          show();
      }
    });
  }

  function autoPeekIfNeeded(){
    const panel=currentPanel();
    if(panel && panel.getAttribute('data-auto-peek')==='true'){
      // Si el panel ya estaba abierto por interacción, no iniciar auto cierre
      const wasLocked = panel.dataset.lockOpen==='true';
      show();
      if(!wasLocked){
        setTimeout(()=>{ scheduleHide(); }, 2200);
      }
      panel.removeAttribute('data-auto-peek');
    }
  }

  function rebindAll(){
    bindLink();
    bindPanelHover();
    autoPeekIfNeeded();
    // Si panel estaba "lockOpen" mantenerlo visible tras re-render
    const panel=currentPanel();
    if(panel && panel.dataset.lockOpen==='true'){
  if(panel && panel.dataset.lockOpen==='true') show();
    }
  }

  // MutationObserver para detectar reemplazo de #cart-preview
  const mo = new MutationObserver((mutations)=>{
    for(const m of mutations){
      if([...m.addedNodes].some(n=> n.id==='cart-preview' || (n.querySelector && n.querySelector('#cart-preview')))){
        rebindAll();
        break;
      }
    }
  });
  ready(()=>{ mo.observe(document.body,{childList:true,subtree:true}); rebindAll(); });
  document.addEventListener('turbo:render', rebindAll);
  document.addEventListener('turbo:before-cache', ()=>{
    // Limpiar bandera para que al restaurar la página se re-bindee correctamente
    const panel=currentPanel(); if(panel) panel.__hoverBound=false;
    linkListenersInstalled=false; currentLink=null;
  });
  document.addEventListener('turbo:after-stream-render', rebindAll);
})();
