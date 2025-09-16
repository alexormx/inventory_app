# JS Migration to jsbundling-rails (esbuild)

## Build / Watch
npm run build
npm run build:watch

## Development Notes
- Turbo + Stimulus se empaquetan juntos.
- ECharts se carga sólo en páginas con data-controller="chart".
- Si falla algo, revisa consola por error en dynamic import.

## Revert to Importmap
1. En layout: reemplazar `<%= javascript_include_tag "application", ... %>` con `<%= javascript_importmap_tags %>`.
2. Restaurar antiguo contenido de `app/javascript/application.js` (Stimulus bootstrap original) si se eliminó.
3. Opcional: eliminar/ignorar `app/javascript/controllers/index.js`.
4. Borrar `app/assets/builds/*` o dejarlo (no se usará).
5. (Opcional) Quitar línea `//= link_tree ../builds` del manifest.
6. (Opcional extremo) `bundle remove jsbundling-rails` y eliminar dependencias npm.
7. Commit: `revert(js): switch back to importmap`.

## Expected Performance Outcome
- Requests JS: ≤ 10 (antes ~80).
- ECharts chunk sólo aparece cuando hay chart_controller presente.
- DOMContentLoaded y Load más bajos (ver Network & Performance panel).

## Heroku Deployment Note
Añadir buildpack Node (heroku/nodejs) antes del buildpack Ruby si no existe:
heroku buildpacks:add --index 1 heroku/nodejs
heroku buildpacks:add --index 2 heroku/ruby

Assets precompile ejecutará `npm run build` (hook de jsbundling).