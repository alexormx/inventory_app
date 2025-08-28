// Mini preview del carrito: muestra panel al hover/foco sobre enlace del carrito
(function(){
  const STATE='__cartPreview';
  if(window[STATE]) return; window[STATE]=true;
  function ready(fn){ if(document.readyState!=='loading') fn(); else document.addEventListener('turbo:load', fn); }

  function bind(){
    const link = document.querySelector('.site-navbar a[href*="/cart"]');
    const panel = document.getElementById('cart-preview');
    if(!link || !panel) return;
    // Evitar múltiples bindings
    if(panel.__bound) return; panel.__bound=true;
    let hideTimer=null;
    function show(){
      clearTimeout(hideTimer);
      panel.hidden=false;
      requestAnimationFrame(()=> panel.classList.add('show'));
    }
    function scheduleHide(){
      hideTimer = setTimeout(()=>{ panel.classList.remove('show'); setTimeout(()=>{ if(!panel.classList.contains('show')) panel.hidden=true; },200); }, 250);
    }
    ['mouseenter','focus'].forEach(ev=> link.addEventListener(ev, show));
    ['mouseleave','blur'].forEach(ev=> link.addEventListener(ev, scheduleHide));
    panel.addEventListener('mouseenter', show);
    panel.addEventListener('mouseleave', scheduleHide);
  }

  ready(bind);
  document.addEventListener('turbo:render', bind);
  document.addEventListener('turbo:after-stream-render', (e)=>{
    if(e.target && e.target.id==='cart-preview'){ bind(); }
    // Asegurar que preview se muestre brevemente después de agregar
    const panel = document.getElementById('cart-preview');
    if(panel && panel.getAttribute('data-auto-peek')==='true'){
      panel.hidden=false; requestAnimationFrame(()=> panel.classList.add('show'));
      setTimeout(()=>{ panel.classList.remove('show'); setTimeout(()=> panel.hidden=true,300); }, 2000);
      panel.removeAttribute('data-auto-peek');
    }
  });
})();
