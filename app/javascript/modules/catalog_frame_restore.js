// La rejilla del catálogo vive en un turbo-frame con data-turbo-action="advance",
// así que paginar y filtrar empujan entradas de historial. Turbo captura la
// instantánea de la página al navegar fuera de ella, y esa captura compite con
// el reemplazo del frame: cuando gana el frame, la entrada de la página 1 queda
// guardada con el contenido de la página 2 y el frame ya marcado `complete`.
// Al volver con Atrás, Turbo reinstala esa instantánea y, como el frame se cree
// completo, nunca vuelve a pedir nada: la URL dice una página y la rejilla
// muestra otra, y no se recupera solo.
//
// La reparación NO puede dispararse por "el src no coincide con la URL": durante
// una navegación hacia adelante ese desajuste es NORMAL y transitorio. La
// secuencia real de Turbo al paginar es
//
//   turbo:frame-render -> turbo:frame-load -> turbo:before-visit ->
//   turbo:visit(action="advance") -> turbo:before-render -> turbo:render -> turbo:load
//
// es decir, el frame llega a la página nueva ANTES de que la visita actualice la
// URL. Reparar ahí devolvía la rejilla a la página anterior y rompía la
// paginación en vivo.
//
// Turbo distingue las restauraciones de forma explícita: al volver con Atrás,
// `popstate` arranca una visita con `action: "restore"`, y ese valor viaja en el
// detail de `turbo:visit`. Se usa esa señal semántica en vez de adivinar por
// tiempos, y `turbo:visit` siempre precede a `turbo:load` en ambos caminos.
const FRAME_ID = "products_grid"

let restoringVisit = false

function frameQuery(frame) {
  const src = frame.getAttribute("src")
  if (!src) return null

  try {
    return new URL(src, window.location.href).search
  } catch {
    return null
  }
}

function resyncRestoredFrame() {
  // La marca NO se consume aquí. Una visita de restauración puede renderizar
  // primero la vista previa cacheada y después la respuesta definitiva, así que
  // dispara más de un `turbo:load`; el estado envenenado puede aparecer en el
  // segundo. Consumirla en el primero dejaba la reparación sin efecto. La marca
  // describe la visita en curso y sólo la reemplaza la visita siguiente.
  if (!restoringVisit) return

  const frame = document.getElementById(FRAME_ID)
  if (!frame) return

  const current = frameQuery(frame)
  // Sin `src` el frame muestra lo que el servidor renderizó para esta URL, que
  // es exactamente lo que se quiere: la restauración quedó limpia.
  if (current === null) return
  if (current === window.location.search) return

  // Restauración envenenada: el frame quedó apuntando a otra página y se cree
  // completo. Quitar `complete` es lo que permite que Turbo vuelva a pedirlo.
  frame.removeAttribute("complete")
  frame.setAttribute("src", window.location.pathname + window.location.search)
}

document.addEventListener("turbo:visit", (event) => {
  restoringVisit = event.detail?.action === "restore"
})

document.addEventListener("turbo:load", resyncRestoredFrame)
