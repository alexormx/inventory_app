// Mini preview del carrito: muestra panel al hover/foco sobre enlace del carrito
(function(){
  const STATE='__cartPreview'; if(window[STATE]) return; window[STATE]=true;
  function ready(fn){ if(document.readyState!=='loading') fn(); else document.addEventListener('turbo:load', fn); }

  let linkBound=false;
  let hideTimer=null;

  function currentPanel(){ return document.getElementById('cart-preview'); }

  function show(){
    const panel=currentPanel(); if(!panel) return;
    clearTimeout(hideTimer);
    panel.hidden=false;
    requestAnimationFrame(()=> panel.classList.add('show'));
  }
  function scheduleHide(){
    const panel=currentPanel(); if(!panel) return;
    hideTimer = setTimeout(()=>{
      panel.classList.remove('show');
      setTimeout(()=>{ const p=currentPanel(); if(p && !p.classList.contains('show')) p.hidden=true; },200);
    },250);
  }

  function bindLink(){
    if(linkBound) return;
    const link=document.querySelector('.site-navbar a[href*="/cart"]');
    if(!link) return;
    ['mouseenter','focus'].forEach(ev=> link.addEventListener(ev, show));
    ['mouseleave','blur'].forEach(ev=> link.addEventListener(ev, scheduleHide));
    linkBound=true;
  }

  function bindPanelHover(){
    const panel=currentPanel(); if(!panel || panel.__hoverBound) return;
    panel.addEventListener('mouseenter', show);
    panel.addEventListener('mouseleave', scheduleHide);
    panel.__hoverBound=true;
  }

  function autoPeekIfNeeded(){
    const panel=currentPanel();
    if(panel && panel.getAttribute('data-auto-peek')==='true'){
      show();
      setTimeout(()=>{ scheduleHide(); }, 2200);
      panel.removeAttribute('data-auto-peek');
    }
  }

  function rebindAll(){
    bindLink();
    bindPanelHover();
    autoPeekIfNeeded();
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
  document.addEventListener('turbo:after-stream-render', rebindAll);
})();
