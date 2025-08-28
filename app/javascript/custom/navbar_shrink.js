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

    let lastState = null;
    let ticking = false;
    const toggle = () => {
      if(ticking) return; // throttle via rAF
      ticking = true;
      requestAnimationFrame(()=>{
        const nav = getNav(); if(!nav){ ticking=false; return; }
        const shouldShrink = window.scrollY > 40;
        if(lastState !== shouldShrink){
          nav.classList.toggle('shrink', shouldShrink);
          lastState = shouldShrink;
          recalc();
        }
        ticking = false;
      });
    };

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
