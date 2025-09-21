document.addEventListener("turbo:frame-load", (event) => {
  const frame = event.target;
  if (frame.id === "modal_frame") {
    const dialog = frame.querySelector("dialog");

    if (dialog && typeof dialog.showModal === "function") {
      dialog.showModal();

      // Evitar scroll del body mientras el dialog está abierto (fallback adicional)
      document.documentElement.classList.add("overlay-open");

      // Cerrar con click en backdrop
      dialog.addEventListener("click", (e) => {
        const rect = dialog.querySelector(".modal-dialog")?.getBoundingClientRect();
        if (!rect) return;
        const clickedInDialog =
          e.clientX >= rect.left &&
          e.clientX <= rect.right &&
          e.clientY >= rect.top &&
          e.clientY <= rect.bottom;
        if (!clickedInDialog) dialog.close();
      });

      // Cerrar con tecla Esc (algunos navegadores lo hacen por defecto)
      const onKey = (e) => { if (e.key === "Escape") dialog.close(); };
      dialog.addEventListener("keydown", onKey);

      // Cierre con botón close
      const closeBtn = dialog.querySelector("#closeModal");
      closeBtn?.addEventListener("click", () => dialog.close());

      // Cierre con botón cancel
      const cancelBtn = dialog.querySelector("#cancelModal");
      cancelBtn?.addEventListener("click", () => dialog.close());

      // Enfoque del primer control del formulario dentro del modal
      const firstInput = dialog.querySelector("input, select, textarea, button");
      firstInput?.focus({ preventScroll: true });

      // Limpiar estado al cerrar
      dialog.addEventListener("close", () => {
        document.documentElement.classList.remove("overlay-open");
        dialog.removeEventListener("keydown", onKey);
      }, { once: true });
    }
  }
});