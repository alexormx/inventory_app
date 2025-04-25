document.addEventListener("turbo:frame-load", (event) => {
  const frame = event.target;
  if (frame.id === "modal_frame") {
    const dialog = frame.querySelector("dialog");

    if (dialog && typeof dialog.showModal === "function") {
      dialog.showModal();

      // Cierre con botón close
      const closeBtn = dialog.querySelector("#closeModal");
      closeBtn?.addEventListener("click", () => dialog.close());

      // Cierre con botón cancel
      const cancelBtn = dialog.querySelector("#cancelModal");
      cancelBtn?.addEventListener("click", () => dialog.close());
    }
  }
});