# frozen_string_literal: true

# DIAGNOSTICO TEMPORAL — rama desechable, no mergear.
#
# Observa el ESTADO del punto de llamada justo antes y justo despues de un
# click, para poder comparar un click sano con el click de "Cerrar sesion" del
# perfil, que es el unico de la suite donde se ha visto entrega nula.
#
# Solo observa. No hace focus(), ni click(), ni reload(), ni preventDefault, ni
# stopPropagation, y no cambia lo que el test pulsa ni lo que asegura.
#
# El grabador se instala con Page.addScriptToEvaluateOnNewDocument para que
# exista desde el primer instante de CADA documento nuevo: los listeners
# puestos despues de una navegacion completa se perderian justo en la ventana
# que nos interesa.
module CallsiteTelemetry
  RECORDER = <<~JS
    (function () {
      if (window.__CS) { return; }
      window.__CS = { events: [], lifecycle: [], installed: Date.now() };

      var record = function (scope) {
        return function (e) {
          try {
            var t = e.target;
            window.__CS.events.push({
              scope: scope,
              type: e.type,
              t: Date.now(),
              trusted: e.isTrusted === true,
              x: (typeof e.clientX === 'number' ? e.clientX : null),
              y: (typeof e.clientY === 'number' ? e.clientY : null),
              target: (t && t.tagName)
                ? (t.tagName + (t.id ? '#' + t.id : '') + (t.className && typeof t.className === 'string' ? '.' + t.className.trim().split(/\\s+/).join('.') : ''))
                : String(t)
            });
          } catch (err) { /* observar nunca debe romper la pagina */ }
        };
      };

      ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(function (type) {
        window.addEventListener(type, record('window'), true);
        document.addEventListener(type, record('document'), true);
      });

      var life = function (e) {
        try {
          window.__CS.lifecycle.push({
            type: e.type,
            t: Date.now(),
            hasFocus: (document.hasFocus ? document.hasFocus() : null),
            visibility: document.visibilityState
          });
        } catch (err) { /* idem */ }
      };

      ['focus', 'blur', 'pageshow', 'pagehide', 'load'].forEach(function (type) {
        window.addEventListener(type, life, true);
      });
      ['visibilitychange', 'DOMContentLoaded', 'turbo:before-render', 'turbo:render', 'turbo:load'].forEach(function (type) {
        document.addEventListener(type, life, true);
      });
    })();
  JS

  SNAPSHOT = <<~JS
    (function (sel) {
      var out = {
        t: Date.now(),
        href: location.href,
        readyState: document.readyState,
        visibility: document.visibilityState,
        hasFocus: (document.hasFocus ? document.hasFocus() : null),
        historyLength: (window.history ? window.history.length : null),
        turboPreview: !!document.querySelector('[data-turbo-preview]'),
        activeElement: null,
        element: null,
        events: [],
        lifecycle: []
      };

      try {
        var a = document.activeElement;
        out.activeElement = a ? (a.tagName + (a.id ? '#' + a.id : '')) : null;
      } catch (e) { out.activeElement = 'ERROR'; }

      try {
        if (window.__CS) {
          out.events = window.__CS.events.slice(0);
          out.lifecycle = window.__CS.lifecycle.slice(0);
        } else {
          out.events = null;
          out.lifecycle = null;
        }
      } catch (e) { /* ignorar */ }

      try {
        var el = null;
        var candidates = document.querySelectorAll(sel);
        for (var i = 0; i < candidates.length; i++) {
          if (candidates[i].offsetParent !== null) { el = candidates[i]; break; }
        }
        if (!el && candidates.length) { el = candidates[0]; }

        if (el) {
          var r = el.getBoundingClientRect();
          var cs = window.getComputedStyle(el);
          var cx = Math.floor(r.left + r.width / 2);
          var cy = Math.floor(r.top + r.height / 2);
          var hit = null;
          try { hit = document.elementFromPoint(cx, cy); } catch (e) { hit = null; }

          var form = el.closest ? el.closest('form') : null;

          out.element = {
            tag: el.tagName,
            type: el.getAttribute('type'),
            isConnected: el.isConnected === true,
            disabled: !!el.disabled,
            rect: { x: r.left, y: r.top, w: r.width, h: r.height },
            center: { x: cx, y: cy },
            visibility: cs.visibility,
            display: cs.display,
            opacity: cs.opacity,
            pointerEvents: cs.pointerEvents,
            inViewport: (cy >= 0 && cy <= window.innerHeight && cx >= 0 && cx <= window.innerWidth),
            viewport: { w: window.innerWidth, h: window.innerHeight },
            scrollY: window.scrollY,
            hitTarget: hit ? (hit.tagName + (hit.id ? '#' + hit.id : '')) : null,
            hitIsElement: hit === el,
            hitIsDescendant: !!(hit && el.contains(hit)),
            hitIsAncestor: !!(hit && hit.contains(el)),
            formAction: form ? form.getAttribute('action') : null,
            formMethod: form ? form.getAttribute('method') : null,
            formTurbo: form ? form.getAttribute('data-turbo') : null
          };
        }
      } catch (e) {
        out.element = { error: String(e) };
      }

      return out;
    })(arguments[0]);
  JS

  # Selector del control de logout del perfil. Hay dos formularios de cierre de
  # sesion en la pagina (el de la barra, dentro del desplegable, y el de la
  # tarjeta de cuenta); el snapshot elige el primero VISIBLE, que es el mismo
  # que resuelve `click_button` de Capybara.
  LOGOUT_SELECTOR = 'form[action="/users/sign_out"] button'
  LOGIN_SUBMIT_SELECTOR = 'form[action="/users/sign_in"] input[type="submit"], form[action="/users/sign_in"] button[type="submit"]'

  class << self
    # Se rescata a proposito: la telemetria no puede cambiar el resultado del
    # ejemplo. Si el navegador no soporta CDP, o la sesion murio, o la pagina
    # esta navegando en el momento del snapshot, se registra el fallo y el test
    # sigue exactamente igual que sin instrumentar.
    def install(page)
      page.driver.browser.execute_cdp('Page.addScriptToEvaluateOnNewDocument', source: RECORDER)
      log('INSTALL', 'ok' => true)
      true
    rescue StandardError => e
      log('INSTALL', 'ok' => false, 'error' => "#{e.class}: #{e.message}")
      false
    end

    def snapshot(page, label, selector)
      data = page.evaluate_script(SNAPSHOT, selector)
      log(label, data)
      data
    rescue StandardError => e
      log(label, 'error' => "#{e.class}: #{e.message}")
      nil
    end

    private

    def log(label, payload)
      puts "CALLSITE #{label} #{payload.to_json}"
    end
  end
end
