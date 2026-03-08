const MODAL_ID = "global-confirm-modal"

function buildModalMarkup() {
  return `
    <div id="${MODAL_ID}" class="confirm-modal" aria-hidden="true" role="dialog" aria-modal="true" aria-labelledby="global-confirm-title">
      <div class="confirm-modal-backdrop" data-confirm="backdrop"></div>
      <div class="confirm-modal-dialog" role="document">
        <div class="confirm-modal-content">
          <div class="confirm-modal-header">
            <div class="confirm-modal-icon" aria-hidden="true">
              <i class="fa-solid fa-triangle-exclamation"></i>
            </div>
            <div>
              <p class="confirm-modal-eyebrow mb-1">Confirmación</p>
              <h2 id="global-confirm-title" class="confirm-modal-title mb-0">Confirmar acción</h2>
            </div>
          </div>
          <div class="confirm-modal-body">
            <p class="confirm-message mb-0"></p>
          </div>
          <div class="confirm-modal-footer d-flex gap-2 justify-content-end">
            <button type="button" class="btn btn-sm btn-outline-secondary" data-confirm="cancel">Cancelar</button>
            <button type="button" class="btn btn-sm btn-danger" data-confirm="ok">Confirmar</button>
          </div>
        </div>
      </div>
    </div>
  `
}

function ensureModal() {
  let modal = document.getElementById(MODAL_ID)

  if (!modal) {
    document.body.insertAdjacentHTML("beforeend", buildModalMarkup())
    modal = document.getElementById(MODAL_ID)
  }

  return modal
}

function candidateElements(element) {
  if (!element) return []

  return [
    element,
    element.form,
    element.closest?.("form"),
    element.parentElement
  ].filter(Boolean)
}

function resolveButtonText(element, fallback, attributeNames) {
  for (const candidate of candidateElements(element)) {
    for (const attributeName of attributeNames) {
      const value = candidate.dataset?.[attributeName]
      if (typeof value === "string" && value.trim().length > 0) return value.trim()
    }
  }

  return fallback
}

export function confirmDialog(message, options = {}) {
  const modal = ensureModal()
  const sourceElement = options.element || null
  const title = options.title || resolveButtonText(sourceElement, "Confirmar acción", ["confirmTitle"])
  const confirmLabel = options.confirmLabel || resolveButtonText(sourceElement, "Confirmar", ["confirmConfirmLabel", "confirmOkLabel"])
  const cancelLabel = options.cancelLabel || resolveButtonText(sourceElement, "Cancelar", ["confirmCancelLabel"])

  const titleNode = modal.querySelector(".confirm-modal-title")
  const messageNode = modal.querySelector(".confirm-message")
  const okBtn = modal.querySelector('[data-confirm="ok"]')
  const cancelBtn = modal.querySelector('[data-confirm="cancel"]')
  const backdrop = modal.querySelector('[data-confirm="backdrop"]')

  titleNode.textContent = title
  messageNode.textContent = message
  okBtn.textContent = confirmLabel
  cancelBtn.textContent = cancelLabel

  return new Promise((resolve) => {
    const escHandler = (event) => {
      if (event.key === "Escape") cleanup(false)
    }

    const cleanup = (confirmed) => {
      okBtn.removeEventListener("click", okHandler)
      cancelBtn.removeEventListener("click", cancelHandler)
      backdrop?.removeEventListener("click", cancelHandler)
      document.removeEventListener("keydown", escHandler)
      modal.classList.remove("show")
      modal.setAttribute("aria-hidden", "true")
      document.body.classList.remove("confirm-modal-open")
      resolve(confirmed)
    }

    const okHandler = (event) => {
      event.preventDefault()
      cleanup(true)
    }

    const cancelHandler = (event) => {
      event.preventDefault()
      cleanup(false)
    }

    okBtn.addEventListener("click", okHandler)
    cancelBtn.addEventListener("click", cancelHandler)
    backdrop?.addEventListener("click", cancelHandler)
    document.addEventListener("keydown", escHandler)

    modal.classList.add("show")
    modal.setAttribute("aria-hidden", "false")
    document.body.classList.add("confirm-modal-open")
    okBtn.focus()
  })
}
