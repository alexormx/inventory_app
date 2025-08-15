document.addEventListener("turbo:load", () => {
  // Toggle mostrar/ocultar piezas dentro del frame de items
  document.body.addEventListener("click", function (event) {
    const toggle = event.target.closest(".inventory-toggle")
    if (toggle) {
      const productId = toggle.id.replace("inventory-toggle-", "")
      const frame = document.getElementById(`inventory-items-frame-${productId}`)
      if (!frame) return

      // Si ya hay contenido en el frame, alternar visibilidad sin recargar
      if (frame.innerHTML.trim() !== "") {
        const items = frame.querySelector(".inventory-items")
        if (items) {
          const isHidden = items.classList.toggle("d-none")
          toggle.textContent = isHidden ? toggle.textContent.replace("Ocultar", "Ver") : toggle.textContent.replace("Ver", "Ocultar")
          event.preventDefault()
        }
      } else {
        // Dejar que Turbo cargue el contenido; luego cambiaremos el texto
        const observer = new MutationObserver(() => {
          const items = frame.querySelector(".inventory-items")
          if (items) {
            toggle.textContent = toggle.textContent.replace("Ver", "Ocultar")
            observer.disconnect()
          }
        })
        observer.observe(frame, { childList: true, subtree: true })
        // no preventDefault para permitir la navegación del turbo-frame
      }
    }
    // Botón: limpiar búsqueda (preserva status actual)
    const clearBtn = event.target.closest(".btn-clear-search")
    if (clearBtn) {
      const form = clearBtn.closest("form")
      if (form) {
        const q = form.querySelector('input[name="q"]')
        if (q) q.value = ""
        form.requestSubmit()
      }
    }
  })

  // Filtro de inventario en cliente: por texto (nombre/SKU) y por status
    // (El filtrado ahora es server-side: q + status por query params)
})
