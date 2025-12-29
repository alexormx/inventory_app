import { Controller } from "@hotwired/stimulus"
import { initLine, initBar, initPie, initSparkline, registerResizeObserver, unregisterResizeObserver } from "../dashboard/charts"
import * as echarts from "echarts"

// data-controller="chart"
// data-chart-type="line|bar|pie|spark"
// data-chart-x="[...json...]"
// data-chart-series="[...json...]"
export default class extends Controller {
  static values = {
    type: String,
    x: String,         // JSON array
    series: String,    // JSON array of series
    data: String       // for sparkline
  }

  connect() {
    // ECharts is bundled statically to avoid dynamic import failures in prod
    if (!echarts) {
      this.showFallback("No se pudo cargar el gráfico")
      return
    }
    this.init(echarts)
  }

  init(echarts) {
    const type = this.typeValue || this.element.dataset.chartType

    const safeParse = (raw, fallback) => {
      if (raw == null) return fallback
      const trimmed = typeof raw === 'string' ? raw.trim() : raw
      if (trimmed === '' || trimmed === '[]' || trimmed === '{}') {
        try {
          // Return parsed simple empty structures if valid JSON empties
          return JSON.parse(trimmed)
        } catch (_) {
          return fallback
        }
      }
      try {
        return JSON.parse(trimmed)
      } catch (_) {
        return fallback
      }
    }

    const x = this.xValue ? safeParse(this.xValue, []) : (this.element.dataset.chartX ? safeParse(this.element.dataset.chartX, []) : [])
    const series = this.seriesValue ? safeParse(this.seriesValue, []) : (this.element.dataset.chartSeries ? safeParse(this.element.dataset.chartSeries, []) : [])
    const data = this.dataValue ? safeParse(this.dataValue, []) : (this.element.dataset.chartData ? safeParse(this.element.dataset.chartData, []) : [])

    // Si no hay datos relevantes y tampoco tipo, no hacer nada para evitar trabajo inútil
    if (!type && series.length === 0 && data.length === 0) return

    // Validación rápida: si faltan ejes/series, mostrar mensaje en lugar de dejar el canvas vacío
    const hasSeries = Array.isArray(series) && series.length > 0
    const hasX = Array.isArray(x) && x.length > 0
    if ((type === 'line' || type === 'bar') && (!hasSeries || !hasX)) {
      this.showFallback('Sin datos para este gráfico')
      return
    }
    if ((type === 'spark' || type === 'sparkline') && !Array.isArray(data)) {
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
      }
    } catch (e) {
      console.error('[chart_controller] render error', e)
      this.showFallback("No se pudo renderizar el gráfico")
    }
  }

  disconnect() {
    if (this.chart) {
      try { this.chart.dispose() } catch (_e) {}
    }
    unregisterResizeObserver(this.element)
  }

  showFallback(message) {
    if (!this.element) return
    this.element.innerHTML = `<div class="text-muted small text-center w-100 h-100 d-flex align-items-center justify-content-center">${message}</div>`
  }
}
