document.addEventListener("turbo:load", () => {
  // Toggle mostrar/ocultar piezas dentro del frame de items
  document.body.addEventListener("click", function (event) {
    const toggle = event.target.closest(".inventory-toggle")
    if (toggle) {
      const productId = toggle.id.replace("inventory-toggle-", "")
      const frame = document.getElementById(`inventory-items-frame-${productId}`)
      if (!frame) return

      const showLoader = () => {
        const loader = frame.querySelector('.inventory-loader')
        if (loader) loader.classList.remove('d-none')
        return loader
      }
      const hideLoader = () => {
        const loader = frame.querySelector('.inventory-loader')
        if (loader) loader.classList.add('d-none')
      }
      const setToggleTo = (state) => {
        if (state === 'showing') {
          toggle.textContent = toggle.textContent.replace('Ver', 'Ocultar')
        } else if (state === 'hidden') {
          toggle.textContent = toggle.textContent.replace('Ocultar', 'Ver')
        }
      }

      const items = frame.querySelector('.inventory-items')

      // Si ya hay contenido en el frame
      if (frame.innerHTML.trim() !== "") {
        if (items) {
          // Alternar visibilidad de items ya cargados
          const isHidden = items.classList.toggle('d-none')
          setToggleTo(isHidden ? 'hidden' : 'showing')
          event.preventDefault()
          return
        } else {
          // Hay contenido pero no items (probablemente solo loader): forzar carga vía src
          showLoader()
          const href = toggle.getAttribute('href')
          if (href) {
            frame.setAttribute('src', href)
            const observer = new MutationObserver(() => {
              const present = frame.querySelector('.inventory-items')
              if (present) {
                hideLoader()
                setToggleTo('showing')
                observer.disconnect()
              }
            })
            observer.observe(frame, { childList: true, subtree: true })
            event.preventDefault()
            return
          }
        }
      } else {
        // Frame vacío: mostrar loader y permitir que Turbo navegue
        showLoader()
        const observer = new MutationObserver(() => {
          const present = frame.querySelector('.inventory-items')
          if (present) {
            hideLoader()
            setToggleTo('showing')
            observer.disconnect()
          }
        })
        observer.observe(frame, { childList: true, subtree: true })
        // No hacemos preventDefault para permitir la navegación del turbo-frame
      }
    }

    // Botón: limpiar búsqueda (preserva status actual)
    const clearBtn = event.target.closest('.btn-clear-search')
    if (clearBtn) {
      const form = clearBtn.closest('form')
      if (form) {
        const q = form.querySelector('input[name="q"]')
        if (q) q.value = ''
        form.requestSubmit()
      }
    }
  })
})
