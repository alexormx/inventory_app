// Mini preview del carrito: muestra panel al hover/foco sobre enlace del carrito
(function(){
  const STATE='__cartPreview'; if(window[STATE]) return; window[STATE]=true;
  function ready(fn){ if(document.readyState!=='loading') fn(); else document.addEventListener('turbo:load', fn); }

  let currentLink=null;
  let hideTimer=null;
  const AUTOHIDE_DELAY=3000; // 3s
  let linkListenersInstalled=false;

  function currentPanel(){ return document.getElementById('cart-preview'); }

  function show(){
    const panel=currentPanel(); if(!panel) return;
    clearTimeout(hideTimer);
    panel.hidden=false;
    requestAnimationFrame(()=> panel.classList.add('show'));
  }
  function hideImmediate(){
    const panel=currentPanel(); if(!panel) return;
    panel.dataset.lockOpen='';
    panel.classList.remove('show');
    setTimeout(()=>{ const p=currentPanel(); if(p && !p.classList.contains('show')) p.hidden=true; },200);
  }

  let lastInteractionAt=0;
  function scheduleHide(){
    clearTimeout(hideTimer);
    const panel=currentPanel(); if(!panel) return;
    hideTimer=setTimeout(()=>{
      const idleFor = Date.now()-lastInteractionAt;
      if(idleFor < 400){ // si hubo interacción muy reciente, reprogramar una vez
        scheduleHide();
      } else {
        hideImmediate();
      }
    }, AUTOHIDE_DELAY);
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
  handlers['mouseenter']=()=>{ lastInteractionAt=Date.now(); show(); clearTimeout(hideTimer); };
  handlers['focus']=()=>{ lastInteractionAt=Date.now(); show(); clearTimeout(hideTimer); };
  handlers['mouseleave']=scheduleHide; // autohide
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
  panel.addEventListener('mouseenter', ()=>{ lastInteractionAt=Date.now(); show(); clearTimeout(hideTimer); });
  panel.addEventListener('mouseleave', scheduleHide);
    panel.__hoverBound=true;
    // Evitar cierre al hacer click en botones internos
    panel.addEventListener('click', (e)=>{
      if(e.target.closest('form')){
          lastInteractionAt=Date.now();
          show();
      }
    });
    // Interceptar submits internos para mantener abierto tras respuesta
    panel.addEventListener('submit', (e)=>{
      if(e.target.closest('.cart-mini-qty-form') || e.target.matches('form[action*="/cart_items/"]')){
          lastInteractionAt=Date.now();
          show();
      }
    });
  }

  function autoPeekIfNeeded(){ /* ya no usado para body-only updates */ }

  function rebindAll(){
    bindLink();
    bindPanelHover();
    autoPeekIfNeeded();
    // Si panel estaba "lockOpen" mantenerlo visible tras re-render
    const panel=currentPanel();
  if(panel && (panel.dataset.lockOpen==='true' || panel.getAttribute('data-lock-open')==='true')){
      panel.dataset.lockOpen='true';
      show();
      // Liberar bloqueo después de 5s sin interacción
      clearTimeout(panel._unlockTimer);
  panel._unlockTimer=setTimeout(()=>{ delete panel.dataset.lockOpen; },5000);
    }
    // Fade superior basado en scroll
    const scrollBox = panel && panel.querySelector('.cart-preview-scroll');
    if(scrollBox && !scrollBox.__fadeBound){
      const toggleFade=()=>{
        if(scrollBox.scrollTop>2) scrollBox.classList.add('has-top-fade'); else scrollBox.classList.remove('has-top-fade');
      };
      scrollBox.addEventListener('scroll', toggleFade, {passive:true});
      toggleFade();
      scrollBox.__fadeBound=true;
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
  document.addEventListener('turbo:after-stream-render', (e)=>{
    const panel=currentPanel();
    if(!panel) return; 
    // Si se reemplazó solo el body, mantener abierto si estaba visible
    if(e.target && e.target.querySelector && e.target.querySelector('#cart-preview-body')){
      if(panel.classList.contains('show')){
        show();
      }
    }
    rebindAll();
  });

  // Cerrar con click en botón close o click fuera
  document.addEventListener('click', (e)=>{
    const panel=currentPanel(); if(!panel) return;
    if(e.target.closest('[data-cart-preview-close]')){ hideImmediate(); return; }
    if(panel.classList.contains('show')){
      if(!panel.contains(e.target) && !(currentLink && currentLink.contains(e.target))){ hideImmediate(); }
    }
  });

  // Cerrar con Escape cuando el panel está abierto y foco dentro o en link
  document.addEventListener('keydown', (e)=>{
    if(e.key==='Escape'){
      const panel=currentPanel(); if(panel && panel.classList.contains('show')) hideImmediate();
    }
  });
  // Fallback: si el usuario mueve rápido el mouse hacia el panel después de salir del link
  document.addEventListener('mousemove', (e)=>{
    const panel=currentPanel(); if(!panel) return;
    if(panel.dataset.lockOpen==='true') return; // ya seguro
    if(panel.matches(':hover')) show();
  }, {passive:true});
})();
