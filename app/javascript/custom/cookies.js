document.addEventListener("turbo:load", () => {
  const banner = document.getElementById("cookie-banner");
  const overlay = document.getElementById("cookie-overlay");

  if (!banner || !overlay) return;

  const localStatus = localStorage.getItem("cookiesAccepted");
  const sessionStatus = sessionStorage.getItem("cookiesAccepted");
  const serverAccepted = banner.dataset.cookiesAccepted === "true"; // viene del servidor

  function hideBanner() {
    banner.remove();
    overlay.remove();
    document.body.classList.remove("no-scroll");
  }

  // ✅ Si aceptó o rechazó en algún medio: no mostrar banner
  if (localStatus === "true" || sessionStatus === "true" || localStatus === "false" || sessionStatus === "false" || serverAccepted) {
    hideBanner();
    return;
  }

  // ❌ Aún no ha aceptado → mostrar banner y bloquear scroll
  banner.classList.remove("d-none");
  overlay.style.display = "block";
  document.body.classList.add("no-scroll");

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