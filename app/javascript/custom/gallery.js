document.addEventListener("turbo:load", () => {
  const mainImage = document.getElementById("main-image");
  const thumbnails = document.querySelectorAll(".thumbnail-image"); // Usa esta clase
  const modal = document.getElementById("image-modal");
  const modalImage = document.getElementById("modal-image");
  const nextBtn = document.getElementById("next-btn");
  const prevBtn = document.getElementById("prev-btn");

  if (!mainImage || thumbnails.length === 0) return;

  let currentIndex = 0;

  function updateMainImage(index) {
    const thumb = thumbnails[index];
    if (!thumb) return;

    // Cambiar imagen principal
    mainImage.src = thumb.dataset.large || thumb.src;
    mainImage.alt = thumb.alt || "";
    mainImage.dataset.index = index;
    currentIndex = index;

    // Marcar thumbnail seleccionado
    thumbnails.forEach(t => t.classList.remove("selected-thumbnail"));
    thumb.classList.add("selected-thumbnail");
  }

  // Click en la imagen principal → abrir modal
  mainImage.addEventListener("click", () => {
    modalImage.src = mainImage.src;
    new bootstrap.Modal(modal).show();
  });

  // Click en thumbnails
  thumbnails.forEach((thumb, index) => {
    thumb.addEventListener("click", () => updateMainImage(index));
  });

  // Navegación con flechas
  nextBtn?.addEventListener("click", () => {
    const newIndex = (currentIndex + 1) % thumbnails.length;
    updateMainImage(newIndex);
  });

  prevBtn?.addEventListener("click", () => {
    const newIndex = (currentIndex - 1 + thumbnails.length) % thumbnails.length;
    updateMainImage(newIndex);
  });

  // Inicializar seleccionado el primero
  updateMainImage(0);
});
