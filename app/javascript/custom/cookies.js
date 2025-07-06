document.addEventListener("turbo:load", () => {
  const banner = document.getElementById("cookie-banner");
  const overlay = document.getElementById("cookie-overlay");

  if (!banner || !overlay) return;

  const localAccepted = localStorage.getItem("cookiesAccepted");
  const sessionAccepted = sessionStorage.getItem("cookiesAccepted");
  const serverAccepted = banner.dataset.cookiesAccepted === "true"; // viene del servidor

  // ✅ Si aceptó en algún medio: no mostrar banner
  if (localAccepted || sessionAccepted || serverAccepted) {
    banner.remove();
    overlay.remove();
    document.body.classList.remove("no-scroll");
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
    banner.remove();
    overlay.remove();
    document.body.classList.remove("no-scroll");

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
});