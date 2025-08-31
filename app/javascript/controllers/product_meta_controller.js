import { Controller } from "@hotwired/stimulus";

// Controla la expansión/colapso de la descripción en el panel resumen
export default class extends Controller {
  static targets = ["descriptionPreview", "descriptionToggle"];

  connect() {
    // Graceful fallback si no hay targets
  }

  toggleDescription(event) {
    event.preventDefault();
    const preview = this.find('[data-description-preview]');
    const btn = this.find('[data-description-toggle]');
    if (!preview || !btn) return;
    const expanded = preview.classList.toggle('expanded');
    if (expanded) {
      preview.style.display = 'block';
      preview.classList.remove('line-clamp');
      btn.textContent = 'Ver menos';
    } else {
      preview.classList.add('line-clamp');
      btn.textContent = 'Ver más';
    }
  }

  find(selector) { return this.element.querySelector(selector); }
}
