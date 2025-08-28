// Toggle light/dark theme with persistence
(function(){
  const KEY = 'site-theme';
  const root = document.documentElement;
  function apply(theme){
    if(theme === 'dark'){ root.setAttribute('data-theme','dark'); }
    else { root.removeAttribute('data-theme'); }
  }
  function stored(){ return localStorage.getItem(KEY); }
  function save(theme){ localStorage.setItem(KEY, theme); }
  function current(){ return root.getAttribute('data-theme') === 'dark' ? 'dark' : 'light'; }

  function toggle(){
    const next = current() === 'dark' ? 'light' : 'dark';
    apply(next); save(next);
    // feedback accesible
    const btn = document.querySelector('[data-theme-toggle]');
    if(btn){ btn.setAttribute('aria-pressed', next === 'dark'); btn.querySelector('i')?.classList.toggle('fa-sun', next==='dark'); btn.querySelector('i')?.classList.toggle('fa-moon', next!=='dark'); }
  }

  document.addEventListener('turbo:load', ()=>{
    const initial = stored(); if(initial) apply(initial);
    const btn = document.querySelector('[data-theme-toggle]');
    if(btn){
      btn.addEventListener('click', toggle);
      btn.setAttribute('aria-pressed', current()==='dark');
    }
  });
})();
