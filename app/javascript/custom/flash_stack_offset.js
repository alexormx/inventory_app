// Ajusta offset inferior del stack de flashes si existe botón WhatsApp
(function(){
  function adjust(){
    const stack = document.getElementById('flash-stack');
    const wa = document.querySelector('.whatsapp-float-button');
    if(!stack) return;
    let extra = 0;
    if(wa){
      const rect = wa.getBoundingClientRect();
      // Si se traslapan (verticalmente en viewport inferior) añade margen extra
      const vh = window.innerHeight;
      if(vh - rect.top < 160) { // heurística
        extra = rect.height + 16; // espacio
      }
    }
    stack.style.marginBottom = extra ? (extra + 'px') : '';
  }
  ['turbo:load','turbo:render','turbo:after-stream-render','resize','scroll'].forEach(ev=>{
    window.addEventListener(ev, adjust, { passive: true });
    document.addEventListener(ev, adjust, { passive: true });
  });
  setTimeout(adjust, 0);
})();