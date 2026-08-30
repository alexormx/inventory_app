# frozen_string_literal: true

# INSTRUMENTACIÓN TEMPORAL DE DIAGNÓSTICO — RAMA DESECHABLE, NO MERGEAR.
#
# Compara, EN EL MISMO ESTADO DEL NAVEGADOR, el click de WebElement contra una
# acción de puntero W3C, únicamente cuando el primero vuelve sin generar ningún
# evento. En entrega normal no altera la semántica del test.
module AccountClickDiagnostics
  TYPES = %w[pointerover pointerenter pointermove pointerdown mousedown pointerup mouseup click].freeze
  DELIVERY = %w[pointerdown mousedown pointerup mouseup click].freeze

  INSTALL = <<~JS
    (() => {
      if (window.__acctTel) { window.__acctTel.events = []; return; }
      window.__acctTel = { events: [] };
      const d = (n) => {
        if (!n) return null;
        if (n === window) return 'window';
        if (n === document) return 'document';
        if (n.nodeType !== 1) return String(n.nodeName || n);
        return (n.id ? '#' + n.id : '') + (n.className ? '.' + String(n.className).slice(0, 40) : n.nodeName);
      };
      const rec = (where) => (e) => window.__acctTel.events.push({
        where, type: e.type, phase: e.eventPhase, target: d(e.target),
        currentTarget: d(e.currentTarget), isTrusted: e.isTrusted,
        defaultPrevented: e.defaultPrevented, cancelBubble: e.cancelBubble,
        t: Math.round(performance.now())
      });
      #{TYPES.inspect}.forEach((t) => {
        window.addEventListener(t, rec('window-capture'), true);
        document.addEventListener(t, rec('document-capture'), true);
        document.addEventListener(t, rec('document-bubble'), false);
      });
    })()
  JS

  SNAPSHOT = <<~JS
    (() => {
      const a = document.getElementById('account');
      const m = document.getElementById('account-menu');
      const r = a ? a.getBoundingClientRect() : null;
      const cx = r ? Math.round(r.left + r.width / 2) : null;
      const cy = r ? Math.round(r.top + r.height / 2) : null;
      const hit = (cx !== null) ? document.elementFromPoint(cx, cy) : null;
      const d = (n) => n ? ((n.id ? '#' + n.id : '') + (n.className ? '.' + String(n.className).slice(0,40) : n.nodeName)) : null;
      return {
        hasFocus: document.hasFocus(), visibility: document.visibilityState,
        activeElement: d(document.activeElement),
        connected: a ? a.isConnected : null,
        stamp: a ? (a.dataset.diagStamp || null) : null,
        enhanced: a ? (a.dataset.dropdownEnhanced || null) : null,
        aria: a ? a.getAttribute('aria-expanded') : null,
        menuShow: m ? m.classList.contains('show') : null,
        rect: r ? { x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) } : null,
        center: { x: cx, y: cy }, hitTarget: d(hit),
        hitIsAccount: !!(hit && a && (hit === a || a.contains(hit))),
        scroll: { x: Math.round(window.scrollX), y: Math.round(window.scrollY) }
      };
    })()
  JS

  def diag_log(label, payload)
    puts "ACCTDIAG #{label} #{payload}"
  end

  def diag_env!
    drv = page.driver.browser
    caps = drv.capabilities
    diag_env = {
      ruby: RUBY_VERSION,
      capybara: Gem.loaded_specs['capybara']&.version&.to_s,
      selenium: Selenium::WebDriver::VERSION,
      browser_name: caps[:browser_name],
      browser_version: caps[:browser_version],
      chromedriver_version: caps['chrome']&.dig('chromedriverVersion'),
      chrome_binary: caps['chrome']&.dig('userDataDir') ? 'runner-default' : nil,
      chromedriver_path_env: ENV.fetch('CHROMEDRIVER_PATH', nil),
      chromewebdriver_env: ENV.fetch('CHROMEWEBDRIVER', nil)
    }
    diag_log('ENV', diag_env.to_json)
  rescue StandardError => e
    diag_log('ENV_ERROR', "#{e.class}: #{e.message[0, 120]}")
  end

  def diag_snapshot
    page.evaluate_script("JSON.stringify(#{SNAPSHOT})")
  end

  def diag_events
    JSON.parse(page.evaluate_script('JSON.stringify(window.__acctTel ? window.__acctTel.events : [])') || '[]')
  end

  # Click instrumentado. Devuelve :delivered o :zero_delivery.
  def diag_click_account!
    page.execute_script(INSTALL)
    page.execute_script("document.getElementById('account').dataset.diagStamp = 'D1';")
    page.execute_script('window.__acctTel.events = [];')

    before = diag_snapshot
    node = find('#account')
    node.click
    after = diag_snapshot
    events = diag_events
    kinds = events.map { |e| e['type'] }.uniq
    delivered = DELIVERY.any? { |k| kinds.include?(k) }

    diag_log('BEFORE_CLICK', before)
    diag_log('AFTER_CLICK', after)
    diag_log('CLICK_EVENTS', { count: events.size, kinds: kinds }.to_json)

    return :delivered if delivered

    st = JSON.parse(after)
    unless st['connected'] == true && st['aria'] == 'false' && st['menuShow'] == false
      diag_log('ZERO_DELIVERY_UNCONFIRMED', after)
      return :zero_delivery_unconfirmed
    end

    diag_log('ZERO_DELIVERY_CONFIRMED', after)
    diag_same_state_w3c!(node, after)
    :zero_delivery
  end

  def diag_same_state_w3c!(node, pre_state)
    page.execute_script('window.__acctTel.events = [];')
    same_node = page.evaluate_script("document.getElementById('account').dataset.diagStamp") == 'D1'
    diag_log('W3C_SAME_NODE', same_node.to_s)

    begin
      page.driver.browser.action.move_to(node.native).pointer_down(:left).pointer_up(:left).perform
      diag_log('W3C_PERFORMED', 'true')
    rescue StandardError => e
      diag_log('W3C_PERFORMED', "false #{e.class}: #{e.message[0, 160]}")
    end

    events = diag_events
    kinds = events.map { |e| e['type'] }.uniq
    post = diag_snapshot
    diag_log('W3C_EVENTS', { count: events.size, kinds: kinds }.to_json)
    diag_log('W3C_RAW', events.to_json)
    diag_log('AFTER_W3C', post)

    pre = JSON.parse(pre_state)
    aft = JSON.parse(post)
    diag_log('DELTA', {
      same_node: same_node,
      same_geometry: pre['rect'] == aft['rect'],
      same_hit_target: pre['hitTarget'] == aft['hitTarget'],
      same_focus: pre['hasFocus'] == aft['hasFocus'] && pre['activeElement'] == aft['activeElement'],
      aria_after: aft['aria'], menu_after: aft['menuShow']
    }.to_json)

    classification =
      if kinds.empty? || DELIVERY.none? { |k| kinds.include?(k) }
        'CASE 2 — BROWSER/SESSION INPUT STATE FAILURE'
      elsif aft['aria'] == 'true' && aft['menuShow'] == true
        'CASE 1 — PRIMITIVE-SPECIFIC NONDELIVERY SUPPORTED'
      else
        'CASE 3 — NEW APPLICATION PATH FAILURE'
      end
    diag_log('CLASSIFICATION', classification)
    raise "ACCOUNT CLICK DIAGNOSTIC: zero-delivery reproduced on CI. #{classification}"
  end
end

RSpec.configure { |c| c.include AccountClickDiagnostics, type: :system }
