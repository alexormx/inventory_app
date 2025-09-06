import { Controller } from "@hotwired/stimulus";

// Controlador de tabs accesible sin depender de Bootstrap JS.
// Requisitos en HTML: data-controller="simple-tabs", botones con data-bs-target="#id-panel".
export default class extends Controller {
  static targets = ["button", "panel"]; 

  connect() {
    this.syncInitial();
    this.buttonTargets.forEach(btn => {
      btn.addEventListener('click', e => {
        e.preventDefault();
        this.activate(btn);
      });
      btn.addEventListener('keydown', e => this.onKeydown(e));
    });
  }

  syncInitial() {
    // Asegura que sólo el panel marcado por el botón .active esté visible
    const activeBtn = this.buttonTargets.find(b => b.classList.contains('active')) || this.buttonTargets[0];
    this.activate(activeBtn, { focus: false });
  }

  onKeydown(e){
    if(!['ArrowRight','ArrowLeft','Home','End'].includes(e.key)) return;
    e.preventDefault();
    const idx = this.buttonTargets.indexOf(e.currentTarget);
    let nextIdx = idx;
    if(e.key === 'ArrowRight') nextIdx = (idx + 1) % this.buttonTargets.length;
    if(e.key === 'ArrowLeft') nextIdx = (idx - 1 + this.buttonTargets.length) % this.buttonTargets.length;
    if(e.key === 'Home') nextIdx = 0;
    if(e.key === 'End') nextIdx = this.buttonTargets.length - 1;
    this.activate(this.buttonTargets[nextIdx]);
  }

  activate(btn, { focus = true } = {}) {
    const targetSelector = btn.getAttribute('data-bs-target');
    if (!targetSelector) return;

    this.buttonTargets.forEach(b => {
      const isActive = b === btn;
      b.classList.toggle('active', isActive);
      b.setAttribute('aria-selected', isActive ? 'true' : 'false');
      b.tabIndex = isActive ? 0 : -1;
    });

    this.panelTargets.forEach(p => {
      const match = ('#' + p.id) === targetSelector;
      p.classList.toggle('active', match);
      p.classList.toggle('show', match);
      p.style.display = match ? 'block' : 'none';
      p.setAttribute('aria-hidden', match ? 'false' : 'true');
    });

    if(focus) btn.focus();
  }
}
