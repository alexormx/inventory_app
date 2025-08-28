// Navbar shrink on scroll (idempotente y compatible con Turbo)
(function(){
  const STATE_KEY = '__navShrinkHandlers';
  function init(){
    // Evitar duplicar listeners: si ya existen, salir (seguirán funcionando con referencia dinámica)
    if(window[STATE_KEY]) return;

    const getNav = () => document.querySelector('.site-navbar');

    const recalc = () => {
      const nav = getNav(); if(!nav) return;
      const banner = document.getElementById('construction-banner');
      const bannerH = banner ? banner.offsetHeight : 0;
      document.documentElement.style.setProperty('--banner-height', bannerH + 'px');
      document.documentElement.style.setProperty('--nav-height', nav.offsetHeight + 'px');
      document.body.style.paddingTop = (bannerH + nav.offsetHeight) + 'px';
    };

    let lastScrollY = window.scrollY;
    let lastAppliedState = null; // true = shrinked
    let ticking = false;
  const DIRECTION_THRESHOLD = 32; // umbral medio para evitar parpadeo
  const MIN_SCROLL_FOR_SHRINK = 70; // disparo más pronto
    let accumulated = 0;
    let lastDirection = null; // 'down' | 'up'

    const evaluate = () => {
      const nav = getNav(); if(!nav) return;
      const currentY = window.scrollY;
      const delta = currentY - lastScrollY;
      // Acumular solo si la dirección se mantiene, reiniciar si cambia
      const dir = delta > 0 ? 'down' : 'up';
      if(dir !== lastDirection){
        accumulated = 0;
        lastDirection = dir;
      }
      accumulated += Math.abs(delta);

      // Reglas:
      // - Contraer (añadir direction-shrink) si se baja y se supera umbral y scrollY > 60
      // - Expandir (quitar) si se sube y acumulado > umbral/2 o se está cerca del top (<60)
      let shouldShrink = lastAppliedState;
      if(dir === 'down' && currentY > MIN_SCROLL_FOR_SHRINK && accumulated > DIRECTION_THRESHOLD){
        shouldShrink = true; // disparo inmediato; animación se encarga de suavizar
      } else if(dir === 'up' && (accumulated > DIRECTION_THRESHOLD/2 || currentY < 60)){
        shouldShrink = false;
      }

      if(shouldShrink !== lastAppliedState){
        nav.classList.toggle('direction-shrink', shouldShrink);
        lastAppliedState = shouldShrink;
        recalc();
        accumulated = 0;
      }
      lastScrollY = currentY;
    };

    const toggle = () => {
      if(ticking) return;
      ticking = true;
      requestAnimationFrame(()=>{ evaluate(); ticking=false; });
    }

    // Guardar referencias para posible depuración
  window[STATE_KEY] = { toggle, recalc };

    // Listeners únicos
    document.addEventListener('turbo:load', ()=>{ toggle(); });
    document.addEventListener('turbo:render', ()=>{ toggle(); });
    document.addEventListener('turbo:after-stream-render', ()=>{ toggle(); });
    window.addEventListener('scroll', toggle, { passive: true });
    window.addEventListener('resize', recalc);

    // Primera ejecución
  toggle();
  }

  init();
})();
