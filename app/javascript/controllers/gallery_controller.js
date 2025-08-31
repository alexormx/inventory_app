import { Controller } from "@hotwired/stimulus";

// Galería de imágenes de producto: thumbnails + navegación prev/next.
// Mejora: asegura un único data-controller que envuelve a la imagen principal y thumbnails.
export default class extends Controller {
  static targets = ["thumbnails"];

  static targets = ["thumbnails", "slides", "track"];

  connect() {
    this.thumbImages = () => Array.from(this.thumbnailsTarget.querySelectorAll('img.thumbnail-image'));
    this.originalSlides = Array.from(this.trackTarget.querySelectorAll('.gallery-slide'));
    this.loopEnabled = this.originalSlides.length > 1;
    if (this.loopEnabled) {
      // Clonar extremos (deep clone) para efecto infinito
      const firstClone = this.originalSlides[0].cloneNode(true);
      const lastClone = this.originalSlides[this.originalSlides.length - 1].cloneNode(true);
      firstClone.classList.add('clone');
      lastClone.classList.add('clone');
      this.trackTarget.insertBefore(lastClone, this.originalSlides[0]);
      this.trackTarget.appendChild(firstClone);
      this.currentIndex = 0; // índice lógico (sobre originales)
      this.physicalIndex = 1; // desplazamiento real en DOM (por clone inicial al frente)
      this.total = this.originalSlides.length;
      this.slideElements = () => Array.from(this.trackTarget.querySelectorAll('.gallery-slide'));
      // Posicionar sin animación en primer slide real
      this.trackTarget.style.transition = 'none';
      this.trackTarget.style.transform = `translateX(-${this.physicalIndex * 100}%)`;
      requestAnimationFrame(() => { // reactivar transición
        this.trackTarget.style.transition = '';
      });
      this.trackTarget.addEventListener('transitionend', (e) => this.onTransitionEnd(e));
    } else {
      this.currentIndex = 0;
      this.physicalIndex = 0;
      this.total = this.originalSlides.length;
      this.slideElements = () => this.originalSlides;
    }
    this.updateThumbs();
    this.updateAria();
  }

  show(event) {
    const el = event.currentTarget;
    const idx = parseInt(el.dataset.index, 10);
    if (!isNaN(idx)) {
      // Considerar adyacencia con wrap (0 <-> last) para animar, todo lo demás teletransporte
      const isAdjacent = (
        idx === this.currentIndex ||
        idx === (this.currentIndex + 1) % this.total ||
        idx === (this.currentIndex - 1 + this.total) % this.total
      );
      const animate = isAdjacent && idx !== this.currentIndex; // no animar si misma
      this.showSlide(idx, animate);
    }
  }

  // Acceso por teclado (delegado)
  keydown(event) {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      this.show(event);
    }
  }

  prev() {
    if (!this.hasThumbnailsTarget) return;
    const target = (this.currentIndex - 1 + this.total) % this.total;
    this.showSlide(target, true, { direction: 'prev' });
  }

  next() {
    if (!this.hasThumbnailsTarget) return;
    const target = (this.currentIndex + 1) % this.total;
    this.showSlide(target, true, { direction: 'next' });
  }

  updateFromIndex(index) { this.showSlide(index); }

  showSlide(index, animate = true, opts = {}) {
    if (!this.loopEnabled) {
      this.currentIndex = index;
      this.trackTarget.style.transform = `translateX(-${index * 100}%)`;
      this.updateThumbs();
      this.updateAria();
      return;
    }

    const target = index % this.total;
    const currentPhysical = this.physicalIndex; // 1..total
    const targetPhysical = target + 1; // offset
    const direction = opts.direction || (targetPhysical > currentPhysical ? 'next' : 'prev');

    // Wrap forward (last -> first)
    if (direction === 'next' && this.currentIndex === this.total - 1 && target === 0) {
      // Animar a clone del primero (total+1) y luego snap a 1 en transitionend
      this.physicalIndex = this.total + 1;
      this.currentIndex = target; // lógico futuro
      this.trackTarget.style.transform = `translateX(-${this.physicalIndex * 100}%)`;
    }
    // Wrap backward (first -> last) con animación hacia izquierda (consistente)
    else if (direction === 'prev' && this.currentIndex === 0 && target === this.total - 1) {
      // Teleport a clone del primero (total+1) sin animación, luego animar un paso a último real (total)
      this.trackTarget.classList.add('no-animate');
      this.physicalIndex = this.total + 1; // clone first al final
      this.trackTarget.style.transform = `translateX(-${this.physicalIndex * 100}%)`;
      void this.trackTarget.offsetWidth; // reflow
      this.trackTarget.classList.remove('no-animate');
      // Ahora animar a último real (total)
      this.physicalIndex = this.total;
      this.currentIndex = target;
      this.trackTarget.style.transform = `translateX(-${this.physicalIndex * 100}%)`;
    }
    // Salto largo (thumbnail no adyacente): teletransporte
    else if (Math.abs(targetPhysical - currentPhysical) > 1) {
      this.trackTarget.classList.add('no-animate');
      this.physicalIndex = targetPhysical;
      this.currentIndex = target;
      this.trackTarget.style.transform = `translateX(-${this.physicalIndex * 100}%)`;
      void this.trackTarget.offsetWidth;
      this.trackTarget.classList.remove('no-animate');
    }
    // Paso normal adyacente
    else {
      this.physicalIndex = targetPhysical;
      this.currentIndex = target;
      this.trackTarget.style.transform = `translateX(-${this.physicalIndex * 100}%)`;
    }

    this.updateThumbs();
    this.updateAria();
  }

  onTransitionEnd(_e) {
    if (!this.loopEnabled) return;
    // Si estamos en clone final (después del último real)
    if (this.physicalIndex === this.total + 1) { // nos movimos desde último real al clone del primero
      this.physicalIndex = 1; // primer real
      this.trackTarget.classList.add('no-animate');
      this.trackTarget.style.transform = `translateX(-${this.physicalIndex * 100}%)`;
      void this.trackTarget.offsetWidth;
      this.trackTarget.classList.remove('no-animate');
      this.currentIndex = 0;
    }
    // Si estamos en clone inicial (antes del primero real)
    if (this.physicalIndex === 0) { // nos movimos desde primer real al clone del último
      this.physicalIndex = this.total; // último real
      this.trackTarget.style.transition = 'none';
      this.trackTarget.style.transform = `translateX(-${this.physicalIndex * 100}%)`;
      requestAnimationFrame(() => { this.trackTarget.style.transition = ''; });
      this.currentIndex = this.total - 1;
    }
  }

  updateThumbs() {
    const thumbs = this.thumbImages();
    thumbs.forEach(t => t.classList.remove('border-primary'));
    if (thumbs[this.currentIndex]) thumbs[this.currentIndex].classList.add('border-primary');
  }

  updateAria() {
    const slides = this.slideElements();
    slides.forEach((s, i) => {
      // i físico => índice lógico = i-1 (por clone al frente) salvo clones
      if (!this.loopEnabled) {
        s.setAttribute('aria-hidden', i === this.currentIndex ? 'false' : 'true');
      } else {
        const logical = i - 1; // clones: -1 y total
        const isVisible = logical === this.currentIndex;
        s.setAttribute('aria-hidden', isVisible ? 'false' : 'true');
      }
    });
  }
}
