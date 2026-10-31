document.addEventListener("turbo:load", () => {
  const banner = document.getElementById("cookie-banner");

  if (!banner) return;

  const localStatus = localStorage.getItem("cookiesAccepted");
  const sessionStatus = sessionStorage.getItem("cookiesAccepted");
  const serverAccepted = banner.dataset.cookiesAccepted === "true"; // viene del servidor

  function hideBanner() {
    banner.remove();
  }

  // ✅ Si aceptó o rechazó en algún medio: no mostrar banner
  if (localStatus === "true" || sessionStatus === "true" || localStatus === "false" || sessionStatus === "false" || serverAccepted) {
    hideBanner();
    return;
  }

  // Aún no decide → mostrar el aviso sin bloquear la página
  banner.classList.remove("d-none");

  document.getElementById("accept-cookies")?.addEventListener("click", () => {
    // ✅ Guardar en storage
    sessionStorage.setItem("cookiesAccepted", "true");
    localStorage.setItem("cookiesAccepted", "true");

    // ✅ Ocultar banner
    hideBanner();

    // 🔐 Si está logueado, registrar aceptación en el servidor
    if (banner.dataset.loggedIn === "true") {
      fetch("/accept_cookies", {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({})
      });
    }
  });

  document.getElementById("reject-cookies")?.addEventListener("click", () => {
    // ❌ Registrar rechazo solo en la sesión
    sessionStorage.setItem("cookiesAccepted", "false");
    hideBanner();
  });
});