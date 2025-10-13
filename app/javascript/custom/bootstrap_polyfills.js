// Lightweight polyfills for Bootstrap-like Collapse and Offcanvas
// Use when Bootstrap JS isn't loaded. Works with Turbo.

(function(){
  let initialized = false;
  function ready(){
    if(initialized) return; initialized = true;
    initCollapse();
    initOffcanvas();
  }

  function initCollapse(){
    const toggles = Array.from(document.querySelectorAll('[data-bs-toggle="collapse"]'));
    toggles.forEach((btn)=>{
      if(btn.dataset.collapseEnhanced === '1') return;
      btn.dataset.collapseEnhanced = '1';
      btn.addEventListener('click', (e)=>{
        e.preventDefault();
        const targetSel = btn.getAttribute('data-bs-target') || btn.getAttribute('href');
        if(!targetSel) return;
        const target = document.querySelector(targetSel);
        if(!target) return;
        const willShow = !target.classList.contains('show');
        target.classList.toggle('show', willShow);
        btn.setAttribute('aria-expanded', String(willShow));
      });
    });
  }

  function initOffcanvas(){
    const triggers = Array.from(document.querySelectorAll('[data-bs-toggle="offcanvas"]'));
    triggers.forEach((btn)=>{
      if(btn.dataset.offcanvasEnhanced === '1') return;
      btn.dataset.offcanvasEnhanced = '1';
      btn.addEventListener('click', (e)=>{
        e.preventDefault();
        const targetSel = btn.getAttribute('data-bs-target');
        if(!targetSel) return;
        const panel = document.querySelector(targetSel);
        if(!panel) return;
        openOffcanvas(panel, btn);
      });
    });

    // Dismiss handlers inside panels
    document.addEventListener('click', (e)=>{
      const dismissBtn = e.target.closest('[data-bs-dismiss="offcanvas"]');
      if(!dismissBtn) return;
      const panel = dismissBtn.closest('.offcanvas');
      if(panel) closeOffcanvas(panel);
    });
  }

  let backdrop;
  function ensureBackdrop(){
    if(backdrop) return backdrop;
    backdrop = document.createElement('div');
    backdrop.className = 'offcanvas-backdrop fade';
    backdrop.setAttribute('data-offcanvas-backdrop', '');
    document.body.appendChild(backdrop);
    backdrop.addEventListener('click', ()=>{
      const panel = document.querySelector('.offcanvas.show');
      if(panel) closeOffcanvas(panel);
    });
    return backdrop;
  }

  function openOffcanvas(panel, btn){
    panel.classList.add('show');
    panel.removeAttribute('aria-hidden');
    document.body.style.overflow = 'hidden';
    const bd = ensureBackdrop();
    requestAnimationFrame(()=> bd.classList.add('show'));
    // focus trap basic
    const focusable = panel.querySelector('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
    if(focusable) setTimeout(()=> focusable.focus(), 0);
    const onEsc = (e)=>{
      if(e.key === 'Escape') closeOffcanvas(panel);
    };
    panel.__onEsc = onEsc;
    document.addEventListener('keydown', onEsc);
  }

  function closeOffcanvas(panel){
    panel.classList.remove('show');
    panel.setAttribute('aria-hidden', 'true');
    document.body.style.overflow = '';
    if(backdrop){ backdrop.classList.remove('show'); }
    if(panel.__onEsc){ document.removeEventListener('keydown', panel.__onEsc); panel.__onEsc = null; }
  }

  document.addEventListener('turbo:load', ready);
  document.addEventListener('turbo:render', ()=>{ initCollapse(); initOffcanvas(); });
})();
