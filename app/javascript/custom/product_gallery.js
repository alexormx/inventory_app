document.addEventListener("turbo:load", () => {
  const mainImage = document.getElementById("main-image");
  const thumbnails = document.querySelectorAll(".thumbnail-image");

  if (!mainImage || thumbnails.length === 0) return;

  thumbnails.forEach((thumb) => {
    thumb.addEventListener("click", () => {
      mainImage.src = thumb.dataset.large;

      // Quitar la clase "selected" de todas las miniaturas
      thumbnails.forEach(t => t.classList.remove("selected-thumbnail"));

      // Agregar clase a la seleccionada
      thumb.classList.add("selected-thumbnail");
    });
  });

  // Navegación con flechas
  const prevBtn = document.getElementById("prev-btn");
  const nextBtn = document.getElementById("next-btn");

  let currentIndex = 0;

  function updateMainImage(index) {
    const newThumb = thumbnails[index];
    if (newThumb) {
      mainImage.src = newThumb.dataset.large;
      thumbnails.forEach(t => t.classList.remove("selected-thumbnail"));
      newThumb.classList.add("selected-thumbnail");
      currentIndex = index;
    }
  }

  prevBtn?.addEventListener("click", () => {
    const newIndex = (currentIndex - 1 + thumbnails.length) % thumbnails.length;
    updateMainImage(newIndex);
  });

  nextBtn?.addEventListener("click", () => {
    const newIndex = (currentIndex + 1) % thumbnails.length;
    updateMainImage(newIndex);
  });
});
