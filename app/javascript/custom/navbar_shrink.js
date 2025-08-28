// Navbar shrink on scroll
(function(){
  const nav = document.querySelector('.site-navbar');
  if(!nav) return;

  const recalc = () => {
    const banner = document.getElementById('construction-banner');
    const bannerH = banner ? banner.offsetHeight : 0;
    document.documentElement.style.setProperty('--banner-height', bannerH + 'px');
    document.documentElement.style.setProperty('--nav-height', nav.offsetHeight + 'px');
    document.body.style.paddingTop = (bannerH + nav.offsetHeight) + 'px';
  };

  const toggle = () => {
    if(window.scrollY > 40) nav.classList.add('shrink'); else nav.classList.remove('shrink');
    recalc();
  };

  document.addEventListener('turbo:load', ()=>{ toggle(); recalc(); });
  document.addEventListener('turbo:render', ()=>{ toggle(); recalc(); });
  window.addEventListener('scroll', toggle, { passive: true });
  window.addEventListener('resize', recalc);
  // initial
  toggle();
})();
