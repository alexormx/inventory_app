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
        } else if (!frame.querySelector("turbo-frame[src]")) {
      // Si el frame no tiene aún items (p.ej. solo loader), mostrar loader y forzar carga navegando al href
      const loader = frame.querySelector('.inventory-loader')
      if (loader) loader.classList.remove('d-none')
          const href = toggle.getAttribute("href")
          if (href) {
            frame.src = href
            const observer = new MutationObserver(() => {
              const ok = frame.querySelector(".inventory-items")
              if (ok) {
        if (loader) loader.classList.add('d-none')
                toggle.textContent = toggle.textContent.replace("Ver", "Ocultar")
                observer.disconnect()
              }
            })
            observer.observe(frame, { childList: true, subtree: true })
          }
        }
      } else {
        // Mostrar loader y dejar que Turbo cargue el contenido; luego cambiaremos el texto
        const loader = frame.querySelector('.inventory-loader')
        if (loader) loader.classList.remove('d-none')

        const observer = new MutationObserver(() => {
          const items = frame.querySelector(".inventory-items")
          if (items) {
            if (loader) loader.classList.add('d-none')
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
