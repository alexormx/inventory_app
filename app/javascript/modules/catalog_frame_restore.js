// La rejilla del catálogo vive en un turbo-frame con data-turbo-action="advance",
// así que paginar y filtrar empujan entradas de historial. Turbo captura la
// instantánea de la página al navegar fuera de ella, y esa captura compite con
// el reemplazo del frame: cuando gana el frame, la entrada de la página 1 queda
// guardada con el contenido de la página 2 y con el frame ya marcado `complete`.
//
// Al volver con Atrás, Turbo reinstala esa instantánea y, como el frame se cree
// completo, nunca vuelve a pedir nada. El resultado es que la URL dice una cosa
// y la rejilla muestra otra: el usuario ve 1 producto donde debería ver 24.
// Verificado que NO se recupera solo (seguía mal a los 25 s), así que no es
// lentitud: la página queda en un estado incoherente hasta que se recarga.
//
// La invariante que se restablece aquí es simple: el `src` del frame tiene que
// coincidir con la consulta de la URL. Cuando no coincide, se vuelve a pedir el
// contenido que corresponde a la URL. En el camino sano no hace nada, porque
// ambos ya concuerdan.
const FRAME_ID = "products_grid"

function frameQuery(frame) {
  const src = frame.getAttribute("src")
  if (!src) return null

  try {
    return new URL(src, window.location.href).search
  } catch {
    return null
  }
}

function resyncCatalogFrame() {
  const frame = document.getElementById(FRAME_ID)
  if (!frame) return

  const current = frameQuery(frame)
  // Sin `src` el frame muestra lo que renderizó el servidor para esta URL, que
  // es justo lo que se quiere; no hay nada que reconciliar.
  if (current === null) return
  if (current === window.location.search) return

  // Volver a pedir lo que corresponde a la URL restaurada. Quitar `complete` es
  // lo que permite que Turbo haga la petición en vez de darse por satisfecho.
  frame.removeAttribute("complete")
  frame.setAttribute("src", window.location.pathname + window.location.search)
}

document.addEventListener("turbo:load", resyncCatalogFrame)
