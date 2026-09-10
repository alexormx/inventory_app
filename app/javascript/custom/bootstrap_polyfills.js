// Lightweight polyfills for Bootstrap-like Collapse and Offcanvas
// Use when Bootstrap JS isn't loaded. Works with Turbo.

(function(){
  let initialized = false;
  function ready(){
    if(initialized) return; initialized = true;
    initCollapse();
    initOffcanvas();
    initTabs();
    initDropdowns();
  }

  function initCollapse(){
    const toggles = Array.from(document.querySelectorAll('[data-bs-toggle="collapse"]'));
    toggles.forEach((btn)=>{
      // Permitir que ciertos toggles gestionen su propio comportamiento
      if (btn.dataset.collapseSkip === 'true') return;
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
    // Bootstrap's CSS for .offcanvas-backdrop has no pointer-events: none
    // when .show is absent — opacity goes to 0 but the element still
    // intercepts every click. Remove the element outright on close
    // (matches Bootstrap's own offcanvas behavior). Next open recreates it.
    if(backdrop){
      backdrop.remove();
      backdrop = null;
    }
    if(panel.__onEsc){ document.removeEventListener('keydown', panel.__onEsc); panel.__onEsc = null; }
  }

  function initTabs(){
    const tabButtons = Array.from(document.querySelectorAll('[data-bs-toggle="tab"]'));
    tabButtons.forEach((btn)=>{
      if(btn.dataset.tabEnhanced === '1') return;
      btn.dataset.tabEnhanced = '1';
      btn.addEventListener('click', (e)=>{
        e.preventDefault();
        const targetSel = btn.getAttribute('data-bs-target');
        if(!targetSel) return;
        const targetPane = document.querySelector(targetSel);
        if(!targetPane) return;

        // Deactivate all tabs in the same tab group
        const tabList = btn.closest('[role="tablist"]');
        if(tabList) {
          const allTabs = tabList.querySelectorAll('[data-bs-toggle="tab"]');
          allTabs.forEach(tab => {
            tab.classList.remove('active');
            tab.setAttribute('aria-selected', 'false');
          });
        }

        // Activate clicked tab
        btn.classList.add('active');
        btn.setAttribute('aria-selected', 'true');

        // Hide all tab panes in the same tab content
        const tabContent = targetPane.closest('.tab-content');
        if(tabContent) {
          const allPanes = tabContent.querySelectorAll('.tab-pane');
          allPanes.forEach(pane => {
            pane.classList.remove('show', 'active');
          });
        }

        // Show target pane
        targetPane.classList.add('show', 'active');
      });
    });
  }

  function initDropdowns(){
    const toggles = Array.from(document.querySelectorAll('[data-bs-toggle="dropdown"]'));
    toggles.forEach((btn)=>{
      // The click owner is delegated to document, so it survives Turbo's cloned
      // snapshots. This marker now reports that a complete toggle/menu pair is
      // covered by that owner; it is not a serializable claim about a listener
      // attached to this particular DOM node.
      if(!dropdownMenuFor(btn)) {
        delete btn.dataset.dropdownEnhanced;
        return;
      }
      btn.dataset.dropdownEnhanced = '1';
    });
  }

  function dropdownMenuFor(btn){
    const parent = btn.closest('.btn-group') || btn.closest('.dropdown') || btn.parentElement;
    return parent ? parent.querySelector('.dropdown-menu') : null;
  }

  function openDropdown(btn, menu){
    closeAllDropdowns();
    menu.classList.add('show');
    btn.setAttribute('aria-expanded','true');
  }

  function closeDropdown(btn, menu){
    menu.classList.remove('show');
    btn.setAttribute('aria-expanded','false');
  }

  function toggleDropdown(btn, menu){
    menu.classList.contains('show') ? closeDropdown(btn, menu) : openDropdown(btn, menu);
  }

  function closeAllDropdowns(){
    document.querySelectorAll('.dropdown-menu.show').forEach(m => m.classList.remove('show'));
    document.querySelectorAll('[data-bs-toggle="dropdown"][aria-expanded="true"]').forEach(b => b.setAttribute('aria-expanded','false'));
  }

  // One delegated owner covers both fresh and Turbo-restored nodes. A Stimulus
  // dropdown action runs on the toggle itself and stops propagation, so it owns
  // that click; when Stimulus is delayed or stopped, the event reaches this
  // fallback instead. Either path produces exactly one state transition.
  document.addEventListener('click', (e)=>{
    const target = e.target instanceof Element ? e.target : null;
    if(!target) return;

    const btn = target.closest('[data-bs-toggle="dropdown"]');
    if(btn){
      const menu = dropdownMenuFor(btn);
      if(!menu) return;

      e.preventDefault();
      e.stopPropagation();
      toggleDropdown(btn, menu);
      return;
    }

    const item = target.closest('.dropdown-menu .dropdown-item');
    if(item){
      const menu = item.closest('.dropdown-menu');
      const parent = menu.closest('.btn-group, .dropdown');
      const owner = parent && parent.querySelector('[data-bs-toggle="dropdown"]');
      if(owner) closeDropdown(owner, menu);
      return;
    }

    if(!target.closest('.btn-group') && !target.closest('.dropdown')){
      closeAllDropdowns();
    }
  });

  // Close dropdowns on Escape
  document.addEventListener('keydown', (e)=>{
    if(e.key === 'Escape') closeAllDropdowns();
  });

  // ---- Modal polyfill (Bootstrap JS isn't loaded) ----
  let modalBackdrop;
  function openModal(modal){
    modal.style.display = 'block';
    modal.removeAttribute('aria-hidden');
    modal.setAttribute('aria-modal', 'true');
    document.body.classList.add('modal-open');
    document.body.style.overflow = 'hidden';
    if(!modalBackdrop){
      modalBackdrop = document.createElement('div');
      modalBackdrop.className = 'modal-backdrop fade';
      document.body.appendChild(modalBackdrop);
      modalBackdrop.addEventListener('click', ()=> closeModal(modal));
    }
    requestAnimationFrame(()=>{ modal.classList.add('show'); modalBackdrop.classList.add('show'); });
    // Nudge any lazy turbo-frame now that the modal is visible.
    modal.querySelectorAll('turbo-frame[loading="lazy"]').forEach((frame)=>{
      if(frame.getAttribute('complete') === null && typeof frame.reload === 'function'){
        try { frame.reload(); } catch(e) { /* ignore */ }
      }
    });
    const focusable = modal.querySelector('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
    if(focusable) setTimeout(()=> focusable.focus(), 0);
    const onEsc = (e)=>{ if(e.key === 'Escape') closeModal(modal); };
    modal.__onEsc = onEsc;
    document.addEventListener('keydown', onEsc);
  }

  function closeModal(modal){
    modal.classList.remove('show');
    modal.style.display = 'none';
    modal.setAttribute('aria-hidden', 'true');
    modal.removeAttribute('aria-modal');
    document.body.classList.remove('modal-open');
    document.body.style.overflow = '';
    if(modalBackdrop){ modalBackdrop.remove(); modalBackdrop = null; }
    if(modal.__onEsc){ document.removeEventListener('keydown', modal.__onEsc); modal.__onEsc = null; }
  }

  document.addEventListener('click', (e)=>{
    const toggle = e.target.closest('[data-bs-toggle="modal"]');
    if(toggle){
      e.preventDefault();
      const sel = toggle.getAttribute('data-bs-target') || toggle.getAttribute('href');
      const modal = sel && document.querySelector(sel);
      if(modal) openModal(modal);
      return;
    }
    const dismiss = e.target.closest('[data-bs-dismiss="modal"]');
    if(dismiss){
      const modal = dismiss.closest('.modal');
      if(modal) closeModal(modal);
    }
  });

  function cleanupModals(){
    document.querySelectorAll('.modal.show').forEach(m => {
      m.classList.remove('show');
      m.style.display = 'none';
      m.setAttribute('aria-hidden', 'true');
    });
    document.querySelectorAll('.modal-backdrop').forEach(el => el.remove());
    document.body.classList.remove('modal-open');
    modalBackdrop = null;
  }

  // Clean up offcanvas state before each Turbo navigation so a backdrop
  // can't leak into the next page and block clicks.
  function cleanupOffcanvas(){
    document.querySelectorAll('.offcanvas.show').forEach(p => {
      p.classList.remove('show');
      p.setAttribute('aria-hidden', 'true');
    });
    document.querySelectorAll('.offcanvas-backdrop, [data-offcanvas-backdrop]').forEach(el => el.remove());
    document.body.style.overflow = '';
    backdrop = null;
  }

  document.addEventListener('turbo:load', ready);
  document.addEventListener('turbo:before-render', ()=>{ cleanupOffcanvas(); cleanupModals(); });
  document.addEventListener('turbo:render', ()=>{ initCollapse(); initOffcanvas(); initTabs(); initDropdowns(); });
})();
