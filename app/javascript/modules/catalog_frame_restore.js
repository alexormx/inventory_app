import { Turbo } from "@hotwired/turbo-rails"

// La rejilla del catálogo vive en un turbo-frame con data-turbo-action="advance",
// así que paginar y filtrar empujan entradas de historial. Eso abre una carrera
// cuando la respuesta del frame lanzada al paginar todavía está EN VUELO y el
// usuario pulsa Atrás: la respuesta tardía llega durante la restauración y hace
// dos destrozos distintos.
//
//   1. LA REJILLA QUEDA EN LA PÁGINA EQUIVOCADA. Turbo captura la instantánea de
//      la página al navegar fuera de ella y esa captura compite con el reemplazo
//      del frame: la entrada de la página 1 queda guardada con el contenido de
//      la página 2 y el frame ya marcado `complete`. Al volver con Atrás, Turbo
//      la reinstala y el frame, creyéndose completo, nunca vuelve a pedir nada.
//
//   2. SE PIERDE EL ADELANTE. Como el frame declara action="advance", Turbo
//      sintetiza una visita de avance para esa respuesta tardía. Esa visita hace
//      pushState estando el usuario en la entrada anterior, y un pushState TRUNCA
//      las entradas hacia adelante: después de Atrás, Adelante ya no tiene a
//      dónde ir. Traza real (la rejilla vuelve bien, pero go_forward no produce
//      ni un popstate porque la entrada ya no existe):
//
//        popstate                      cards=1   hist=3  href=página1  src=página2
//        turbo:visit action="restore"
//        turbo:frame-render                     <- respuesta tardía de la paginación
//        turbo:visit action="advance"           <- pushState: mata el Adelante
//        turbo:load  cards=1  href=página1  src=página2
//
// Ambos se arreglan aquí, y hacen falta los dos: reparar sólo la rejilla
// convierte "falla al volver" en "falla al avanzar".
//
// POR QUÉ NO BASTA COMPARAR src CON LA URL
//
// Durante una navegación hacia adelante ese desajuste es NORMAL y transitorio:
//
//   turbo:frame-render -> turbo:frame-load -> turbo:before-visit ->
//   turbo:visit(action="advance") -> turbo:before-render -> turbo:render -> turbo:load
//
// el frame llega a la página nueva ANTES de que la visita actualice la URL.
// Reparar ahí devolvía la rejilla a la página anterior y rompía la paginación en
// vivo. Tampoco basta con esperar a `turbo:load`: bajo CPU contendida ese
// `turbo:load` puede llegar con la URL todavía sin actualizar, y medido así la
// rejilla volvía a la página 1 nada más paginar (la regresión de #149). Por eso
// se usa la señal semántica de Turbo (`action: "restore"`) y no una heurística
// de tiempos.
//
// POR QUÉ LA MARCA NO SE PISA CON CUALQUIER VISITA
//
// Antes la marca se reasignaba en cada `turbo:visit` (`marca = action ===
// "restore"`). La visita de avance sintetizada en (2) llega entre el "restore" y
// el `turbo:load` y la borraba, así que la reparación se saltaba. Una visita que
// no es restauración sólo puede retirar la marca cuando la restauración anterior
// ya produjo su `turbo:load`; si llega antes, es consecuencia de esa misma
// restauración.
const FRAME_ID = "products_grid"
const PUSHING_ACTION = "advance"
const NON_PUSHING_ACTION = "replace"

// Hay una restauración cuyo resultado todavía no se ha comprobado.
let pendingRestore = false
// Esa restauración ya llegó a `turbo:load` al menos una vez.
let restoreSettled = false

function catalogFrame() {
  return document.getElementById(FRAME_ID)
}

function frameQuery(frame) {
  const src = frame.getAttribute("src")
  if (!src) return null

  try {
    return new URL(src, window.location.href).search
  } catch {
    return null
  }
}

// La petición que lanza la PROPIA reparación tampoco puede empujar historial, y
// el atributo NO sirve para conseguirlo. Turbo lee `data-turbo-action` una sola
// vez, cuando una navegación real del frame propone su visita, y guarda esa
// acción en el delegado del frame. A partir de ahí CADA respuesta del frame
// llama a `changeHistory()` con la acción guardada, también las cargas
// disparadas cambiando `src` a mano. Por eso poner "replace" en el atributo
// antes de tocar `src` no cambiaba nada: tras ordenar el catálogo la acción
// guardada seguía siendo "advance" y la reparación hacía pushState. Estando el
// usuario en la entrada anterior (acaba de pulsar Atrás), ese pushState TRUNCA
// el Adelante: justo el fallo que este módulo existe para evitar. Traza real:
//
//   history.pushState url=/catalog :: History.update
//                                  << FrameController.changeHistory
//                                  << #loadFrameResponse << loadResponse
//   ...y la entrada ordenada ya no existe cuando el usuario pulsa Adelante.
//
// `turbo:before-visit` tampoco alcanza a esto: la mutación de historial la hace
// el frame directamente, sin pasar por ninguna visita cancelable.
//
// `Turbo.visit(url, { frame, action })` es la vía pública que sí fija la acción
// guardada. Con "replace" la carga reescribe la entrada actual —la misma URL en
// la que ya estamos— en vez de empujar una nueva, y el Adelante sobrevive.
function repairWithoutHistoryPush(frame, url) {
  frame.removeAttribute("complete")
  Turbo.visit(url, { frame: FRAME_ID, action: NON_PUSHING_ACTION })
}

function resyncRestoredFrame() {
  // La marca NO se consume aquí. Una visita de restauración puede renderizar
  // primero la vista previa cacheada y después la respuesta definitiva, así que
  // dispara más de un `turbo:load`; el estado envenenado puede aparecer en el
  // segundo. La marca describe la restauración en curso y sólo la retira una
  // navegación posterior del usuario.
  if (!pendingRestore) return

  restoreSettled = true

  const frame = catalogFrame()
  if (!frame) return

  const current = frameQuery(frame)
  // Sin `src` el frame muestra lo que el servidor renderizó para esta URL, que
  // es exactamente lo que se quiere: la restauración quedó limpia.
  if (current === null || current === window.location.search) return

  // Restauración envenenada: el frame quedó apuntando a otra página y se cree
  // completo. Quitar `complete` es lo que permite que Turbo vuelva a pedirlo.
  repairWithoutHistoryPush(frame, window.location.pathname + window.location.search)
}

document.addEventListener("turbo:visit", (event) => {
  if (event.detail?.action === "restore") {
    pendingRestore = true
    restoreSettled = false
    return
  }

  // Visita que no es restauración. Sólo retira la marca si la restauración
  // anterior ya se resolvió; en caso contrario procede de una respuesta de frame
  // tardía dentro de esa misma restauración y pisarla reabriría el fallo.
  if (!pendingRestore || restoreSettled) {
    pendingRestore = false
    restoreSettled = false
  }
})

// La respuesta tardía de la paginación es la que mata el Adelante, y no se puede
// desactivar por atributo: Turbo fija la acción de la visita cuando ARRANCA la
// navegación del frame (al pulsar el enlace), no cuando llega la respuesta.
// Medido: poner "replace" durante la restauración no cambiaba nada y la visita
// seguía llegando como "advance".
//
// Lo que sí se puede es no dejarla ocurrir. `turbo:before-visit` NO se dispara
// para navegaciones de historial, así que cancelar aquí no toca ni el Atrás ni
// el Adelante del usuario: sólo alcanza a una visita propuesta mientras una
// restauración sigue sin resolverse, que es exactamente la respuesta tardía. La
// rejilla no se queda mal por cancelarla: el `turbo:load` de la restauración
// pasa igualmente por la reparación de arriba.
document.addEventListener("turbo:before-visit", (event) => {
  if (pendingRestore && !restoreSettled) {
    event.preventDefault()
  }
})

document.addEventListener("turbo:load", resyncRestoredFrame)
