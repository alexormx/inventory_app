// Mini preview del carrito: muestra panel al hover/foco sobre enlace del carrito
(function(){
  const STATE='__cartPreview';
  if(window[STATE]) return; window[STATE]=true;
  function ready(fn){ if(document.readyState!=='loading') fn(); else document.addEventListener('turbo:load', fn); }
  ready(()=>{
    const link = document.querySelector('.site-navbar a[href*="/cart"]');
    const panel = document.getElementById('cart-preview');
    if(!link || !panel) return;

    let hideTimer=null;
    function show(){
      clearTimeout(hideTimer);
      panel.hidden=false;
      requestAnimationFrame(()=> panel.classList.add('show'));
    }
    function scheduleHide(){
      hideTimer = setTimeout(()=>{ panel.classList.remove('show'); setTimeout(()=>{ if(!panel.classList.contains('show')) panel.hidden=true; },200); }, 250);
    }

    link.addEventListener('mouseenter', show);
    link.addEventListener('focus', show);
    link.addEventListener('mouseleave', scheduleHide);
    link.addEventListener('blur', scheduleHide);
    panel.addEventListener('mouseenter', show);
    panel.addEventListener('mouseleave', scheduleHide);

    // Actualizar contenido con Turbo Stream después de agregar producto: reutilizar flash stream hook
    document.addEventListener('turbo:after-stream-render', ()=>{
      // Podría implementarse un endpoint parcial; por ahora rehacer menores datos via fetch JSON
      // (optimización futura)
    });
  });
})();
