# Sincronización HLJ: operación y límites

## Por qué existe este documento

El 2026-08-01 `Suppliers::Hlj::TomicaRecentArrivalsJob` pasó de procesar 1 producto
en 4 segundos a procesar 5,313 en ~95 minutos. Con `SOLID_QUEUE_IN_PUMA=true` el
job corre dentro del dyno web (Basic, 512 MB), así que el RSS quedó en 939–978 MB
(≈190 % de la cuota) y Heroku emitió R14 de forma continua hasta el reinicio.

La causa fue que `date_arrivals_within_days` / `date_added_within_days` son
filtros **remotos** (`dateArrivals=-10` en la URL de HLJ). Cuando HLJ deja de
honrarlos, la búsqueda devuelve el catálogo completo y el job no tenía ningún
freno local.

## Arquitectura actual

| Componente | Qué hace | Costo por corrida |
| --- | --- | --- |
| `Suppliers::Hlj::DiscoveryService` | Recorre el listado y da de alta SKUs nuevos | 1 GET por página + 1 GET de detalle **solo** por SKU nuevo |
| `Suppliers::Hlj::StatusSyncService` | Refresca estado y precio del catálogo conocido | 1 GET por lote de 50 SKUs, cero HTML |
| `Suppliers::Hlj::LivePriceService` | Cliente del endpoint `livePrice` por lotes | — |
| `Suppliers::Catalog::ImportCatalogItemService` | Alta / sincronización completa | Escribe solo si algo cambió |
| `Suppliers::Catalog::UpdateListingStateService` | Actualización ligera: estado, precio y marcas de tiempo | Escribe solo si algo cambió |

`detail_policy` controla hasta dónde llega el descubrimiento:

- `all` — descarga la página de detalle de cada ítem (sincronización completa,
  semanal y manual).
- `new_only` — solo para SKUs que aún no existen (jobs diarios).
- `none` — nunca.

## Límites

| Variable | Default | Efecto |
| --- | --- | --- |
| `HLJ_DAILY_MAX_PAGES` | 5 | Páginas de listado por job diario |
| `HLJ_DAILY_MAX_ITEMS` | 150 | Productos por job diario |
| `HLJ_LIVE_PRICE_BATCH_SIZE` | 50 | SKUs por petición a `livePrice` |

El recorrido también se corta por reloj aunque los límites por página fallen:

- `DiscoveryService::DAILY_MAX_DURATION_SECONDS` (900) para los jobs diarios.
- `DiscoveryService::DEFAULT_MAX_DURATION_SECONDS` (3600) para el sync completo
  semanal y las corridas manuales, que por definición recorren más.

Cuando se agota, la corrida termina como `completed` con
`stopped_reason: "max_duration_seconds"` en metadata: es una señal a revisar, no
un fallo.

Si HLJ reporta más de `DEFAULT_PAGE_ANOMALY_THRESHOLD` (20) páginas, la corrida
lo registra en el log y en `SupplierSyncRun#metadata`:

```
page_count_anomaly: true
remote_total_pages: 240
pages_traversed: 5
```

Esa bandera es la señal de que el filtro remoto volvió a romperse.

## Calendario (`config/recurring.yml`, producción, UTC)

| Hora | Job |
| --- | --- |
| 05:00 | `TomicaRecentAdditionsJob` (descubrimiento, `new_only`) |
| 05:20 | `TomicaRecentArrivalsJob` (descubrimiento, `new_only`) |
| 05:40 | `TomicaStatusSyncJob` (estado y precio, sin HTML) |
| Lunes 06:00 | `WeeklyDiscoveryJob` (sincronización completa, `detail_policy: all`) |

## Mover Solid Queue a su propio dyno

Mientras `SOLID_QUEUE_IN_PUMA=true`, cualquier job comparte los 512 MB del dyno
web. Las optimizaciones de arriba bastan para volver a entrar en la cuota, pero
la separación sigue siendo la mejora estructural.

**No está aplicada.** El `Procfile` debe declarar el proceso, sin escalarlo:

```
worker: bundle exec rake solid_queue:start
```

Publicar esa declaración no mueve la cola por sí solo: el tipo nuevo debe seguir
en `worker=0` y `SOLID_QUEUE_IN_PUMA` debe permanecer activo hasta una ventana
operativa aprobada. El worker adicional tiene costo y exige autorización
separada.

### Rollout futuro (no ejecutar como parte del PR)

1. Fusionar y desplegar primero el `Procfile`; confirmar `/up` y la versión
   esperada.
2. Verificar con `heroku ps -a evening-anchorage-70843` que sólo está activo
   `web.1` y que no existe `worker.1` (`worker=0`). No cambiar todavía la
   configuración.
3. Elegir una ventana segura. Los jobs permanecen durables en PostgreSQL durante
   el breve cambio, pero no se procesarán entre los pasos 4 y 5.
4. Desactivar el supervisor de Puma **eliminando** la variable:

   ```bash
   heroku config:unset SOLID_QUEUE_IN_PUMA -a evening-anchorage-70843
   ```

   No usar `SOLID_QUEUE_IN_PUMA=false`: para `ENV['SOLID_QUEUE_IN_PUMA']`, la
   cadena `"false"` sigue siendo verdadera y arrancaría un segundo supervisor.
5. Inmediatamente después, arrancar exactamente un worker:

   ```bash
   heroku ps:scale worker=1 -a evening-anchorage-70843
   ```

6. Confirmar que `web.1` y `worker.1` están `up`, que `/up` responde 200 y que
   los logs muestran el supervisor únicamente en `worker.1`. Tras dejar pasar el
   umbral de heartbeat/pruning (5 minutos), verificar sólo conteos, nunca
   payloads ni argumentos de jobs:

   ```bash
   heroku run --no-tty bin/rails runner '
     cutoff = SolidQueue.process_alive_threshold.ago
     puts SolidQueue::Process.where(last_heartbeat_at: cutoff..).group(:kind).count.inspect
   ' -a evening-anchorage-70843
   ```

   Con la configuración por defecto se espera exactamente un `Supervisor`, un
   `Dispatcher`, un `Worker` y un `Scheduler`.
7. Verificar que la cola avanza comparando sólo conteos agregados antes y después
   de un job programado conocido:

   ```bash
   heroku run --no-tty bin/rails runner '
     puts({
       ready: SolidQueue::ReadyExecution.count,
       claimed: SolidQueue::ClaimedExecution.count,
       unfinished: SolidQueue::Job.where(finished_at: nil).count,
       failed: SolidQueue::FailedExecution.count
     }.inspect)
   ' -a evening-anchorage-70843
   ```

   No imprimir argumentos, payloads, credenciales ni configuración completa.
8. Vigilar memoria del dyno web y eventos `R14` por al menos una hora, incluida
   una ejecución real de jobs. El objetivo es que el proceso web deje de cargar
   Supervisor/Dispatcher/Worker/Scheduler; no cambiar `MALLOC_ARENA_MAX` ni
   `RAILS_MAX_THREADS` como parte de este rollout.

### Rollback futuro

Evitar dos supervisores usando este orden exacto:

1. `heroku ps:scale worker=0 -a evening-anchorage-70843`
2. `heroku config:set SOLID_QUEUE_IN_PUMA=true -a evening-anchorage-70843`
3. Confirmar `/up`, esperar el heartbeat del supervisor dentro de `web.1` y
   comprobar que la cola vuelve a avanzar.

El intervalo entre 1 y 2 pausa el procesamiento, pero no pierde jobs porque la
cola usa PostgreSQL. No revertir el `Procfile` durante una emergencia: dejar el
tipo declarado en cero simplifica la recuperación y no consume un dyno.

## Verificación post-deploy

```bash
# La corrida diaria respetó los límites
heroku run rails runner '
  run = SupplierSyncRun.where(mode: "tomica_recent_arrivals_daily").order(created_at: :desc).first
  puts run.slice(:status, :processed_count, :created_count, :updated_count, :skipped_count, :error_count).inspect
  puts run.metadata.slice("detail_policy", "detail_fetch_count", "unchanged_count",
                          "pages_traversed", "remote_total_pages", "page_count_anomaly",
                          "duration_seconds").inspect
' -a evening-anchorage-70843

# El refresco de estado tocó el catálogo sin bajar HTML
heroku run rails runner '
  run = SupplierSyncRun.where(mode: "hlj_status_sync").order(created_at: :desc).first
  puts run.slice(:status, :processed_count, :updated_count, :skipped_count, :error_count).inspect
  puts run.metadata.slice("unchanged_count", "status_changed_count", "price_changed_count",
                          "live_price_failed_skus").inspect
' -a evening-anchorage-70843

# needs_review dejó de inflarse
heroku run rails runner 'puts SupplierCatalogItem.where(needs_review: true).count' -a evening-anchorage-70843

# Memoria después de la ventana 05:00–06:00 UTC
heroku logs --tail --app evening-anchorage-70843 | grep -E "R14|Process running mem"
```

Señales de que algo sigue mal:

- `duration_seconds` cercano a 1800 → el recorrido se cortó por tiempo.
- `page_count_anomaly: true` de forma sostenida → HLJ dejó de aplicar el filtro
  de fechas; revisar `Suppliers::Hlj::SearchQuery`.
- `live_price_failed_skus` alto → el endpoint `livePrice` está fallando; bajar
  `HLJ_LIVE_PRICE_BATCH_SIZE`.
