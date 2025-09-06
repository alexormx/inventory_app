import { Controller } from "@hotwired/stimulus";

// Controlador minimal para acordeones (evita dependencia de Bootstrap JS)
// Uso: data-controller="simple-accordion" en un contenedor
// Botón: data-action="click->simple-accordion#toggle" data-simple-accordion-target="button" data-target-id="elementId"
// Panel: id="elementId" data-simple-accordion-target="panel"
export default class extends Controller {
  static targets = ["button", "panel"]; 

  connect() {
    // Inicial: ocultar todos menos los primeros (opcional)
    this.panelTargets.forEach((p,i)=>{
      if(!p.classList.contains('show')) this.hide(p);
    });
  }

  toggle(e){
    const btn = e.currentTarget;
    const id = btn.getAttribute('data-target-id');
    const panel = this.panelTargets.find(p => p.id === id);
    if(!panel) return;

    const isOpen = panel.dataset.open === 'true';
    // Cerrar otros (comportamiento acordeón)
    this.panelTargets.forEach(p => this.hide(p));
    this.buttonTargets.forEach(b => b.classList.add('collapsed'));

    if(!isOpen){
      this.show(panel);
      btn.classList.remove('collapsed');
    } else {
      btn.classList.add('collapsed');
    }
  }

  show(panel){
    panel.style.display = 'block';
    panel.classList.add('show');
    panel.dataset.open = 'true';
  }

  hide(panel){
    panel.style.display = 'none';
    panel.classList.remove('show');
    panel.dataset.open = 'false';
  }
}
