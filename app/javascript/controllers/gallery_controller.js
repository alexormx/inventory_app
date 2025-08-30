import { Controller } from "@hotwired/stimulus";

// Controla el swap de la imagen principal al hacer click en miniaturas
// Usa data-gallery-large-value en thumbs
export default class extends Controller {
  static targets = ["thumbnails"];

  show(event) {
    const el = event.currentTarget;
    const largeUrl = el.dataset.galleryLargeValue;
    if (!largeUrl) return;
    const picture = this.element.querySelector('picture');
    const img = picture ? picture.querySelector('img') : this.element.querySelector('img');
    if (!img) return;

    // Reemplazo rápido solo src; en una versión avanzada regeneraríamos <source> con otros formatos.
    img.src = largeUrl;
    img.removeAttribute('srcset'); // evitar que navegador mantenga antiguo set

    // Actualizar selección visual
    this.thumbnailsTarget.querySelectorAll('img.thumbnail-image').forEach(t => t.classList.remove('border-primary'));
    el.classList.add('border-primary');
  }
}
