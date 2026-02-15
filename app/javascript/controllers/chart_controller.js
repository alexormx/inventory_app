import { Controller } from "@hotwired/stimulus"
import { initLine, initBar, initStackedBar, initPie, initSparkline, registerResizeObserver, unregisterResizeObserver } from "../dashboard/charts"
import * as echarts from "echarts"

// data-controller="chart"
// data-chart-type-value="line|bar|stacked|pie|spark"
// data-chart-x-value="[...json...]"
// data-chart-series-value="[...json...]"
// data-chart-data-value="[...json...]"  (sparkline only)
export default class extends Controller {
  static values = {
    type: String,
    x: String,
    series: String,
    data: String
  }

  connect() {
    if (!echarts) {
      this.showFallback("No se pudo cargar ECharts")
      return
    }
    // Defer initialization to next animation frame so the container
    // has its final dimensions (fixes zero-size init issue with Turbo)
    this._raf = requestAnimationFrame(() => {
      this._raf = null
      this.initChart()
    })
  }

  initChart() {
    const type = this.typeValue || this.element.dataset.chartType
    const x = this.safeParse(this.xValue || this.element.dataset.chartX, [])
    const series = this.safeParse(this.seriesValue || this.element.dataset.chartSeries, [])
    const data = this.safeParse(this.dataValue || this.element.dataset.chartData, [])

    if (!type && series.length === 0 && data.length === 0) return

    const hasSeries = Array.isArray(series) && series.length > 0
    const hasX = Array.isArray(x) && x.length > 0
    if ((type === 'line' || type === 'bar' || type === 'stacked') && (!hasSeries || !hasX)) {
      this.showFallback('Sin datos para este gráfico')
      return
    }
    if (type === 'pie' && (!Array.isArray(series) || series.length === 0)) {
      this.showFallback('Sin datos para este gráfico')
      return
    }
    if ((type === 'spark' || type === 'sparkline') && (!Array.isArray(data) || data.length === 0)) {
      this.showFallback('Sin datos para este gráfico')
      return
    }

    let chart
    try {
      switch (type) {
        case 'line':
          chart = initLine(echarts, this.element, { x, series })
          break
        case 'bar':
          chart = initBar(echarts, this.element, { x, series })
          break
        case 'stacked':
          chart = initStackedBar(echarts, this.element, { x, series })
          break
        case 'pie':
          chart = initPie(echarts, this.element, { series })
          break
        case 'spark':
        case 'sparkline':
          chart = initSparkline(echarts, this.element, { data })
          break
        default:
          chart = initLine(echarts, this.element, { x, series })
      }
      if (chart) {
        this.chart = chart
        registerResizeObserver(this.element, chart)
        // Force a resize after a short delay to handle any CSS transitions
        setTimeout(() => { try { chart.resize() } catch (_) {} }, 150)
      }
    } catch (e) {
      console.error('[chart_controller] render error', e)
      this.showFallback("Error al renderizar el gráfico")
    }
  }

  disconnect() {
    if (this._raf) { cancelAnimationFrame(this._raf); this._raf = null }
    if (this.chart) {
      try { this.chart.dispose() } catch (_e) {}
      this.chart = null
    }
    unregisterResizeObserver(this.element)
  }

  safeParse(raw, fallback) {
    if (raw == null || raw === '') return fallback
    const trimmed = typeof raw === 'string' ? raw.trim() : raw
    if (trimmed === '' || trimmed === '[]' || trimmed === '{}') {
      try { return JSON.parse(trimmed) } catch (_) { return fallback }
    }
    try { return JSON.parse(trimmed) } catch (_) { return fallback }
  }

  showFallback(message) {
    if (!this.element) return
    this.element.innerHTML = `<div class="text-muted small text-center w-100 h-100 d-flex align-items-center justify-content-center">${message}</div>`
  }
}
