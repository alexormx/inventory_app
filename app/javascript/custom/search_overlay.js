// Control de overlay de búsqueda global
(function(){
  const STATE_KEY='__searchOverlay';
  function init(){
    if(window[STATE_KEY]) return; // idempotente
    const overlay = () => document.getElementById('search-overlay');
    const input = () => overlay()?.querySelector('input[type="search"]');
    const clearBtn = () => overlay()?.querySelector('[data-search-clear]');

    function openOverlay(){
      const ov = overlay(); if(!ov) return;
      ov.hidden = false; ov.setAttribute('aria-hidden','false');
      document.body.classList.add('overlay-open');
      setTimeout(()=>{ input()?.focus(); }, 0);
    }
    function closeOverlay(){
      const ov = overlay(); if(!ov) return;
      ov.setAttribute('aria-hidden','true');
      ov.hidden = true;
      document.body.classList.remove('overlay-open');
    }
    function toggleOverlay(force){
      const ov = overlay(); if(!ov) return;
      if(force === true) return openOverlay();
      if(force === false) return closeOverlay();
      ov.hidden ? openOverlay() : closeOverlay();
    }

    function onKey(e){
      // Abrir con / excepto si se escribe dentro de inputs/textarea
      if(e.key === '/' && !e.ctrlKey && !e.metaKey && !e.altKey){
        const target = e.target;
        const tag = target.tagName;
        if(tag !== 'INPUT' && tag !== 'TEXTAREA' && !target.isContentEditable){
          e.preventDefault(); openOverlay();
        }
      }
      if(e.key === 'Escape'){ closeOverlay(); }
    }

    document.addEventListener('click', (e)=>{
      const t = e.target;
      if(t.closest('[data-search-open]')){ openOverlay(); }
      if(t.closest('[data-search-close]')){ closeOverlay(); }
      if(t.closest('[data-search-clear]')){
        const inp = input(); if(inp){ inp.value=''; inp.focus(); clearBtn().hidden = true; }
      }
    });

    document.addEventListener('keydown', onKey);

    document.addEventListener('input', (e)=>{
      if(e.target === input()){
        clearBtn().hidden = !e.target.value;
      }
    });

    // Cerrar si se hace navegación Turbo
    document.addEventListener('turbo:before-visit', closeOverlay);

    window[STATE_KEY] = { openOverlay, closeOverlay };
  }
  init();
})();
