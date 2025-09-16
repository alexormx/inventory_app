import { Controller } from "@hotwired/stimulus"
import { initLine, initBar, initPie, initSparkline, registerResizeObserver } from "../dashboard/charts"

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

  async connect() {
    // Lazy load ECharts only if the element exists
    let echarts
    try {
      echarts = (await import("echarts")).default
    } catch (e) {
      console.warn("[chart_controller] Error loading echarts", e)
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
      if (chart) registerResizeObserver(this.element, chart)
    } catch (_e) {
      // Silencioso: evitamos bloquear otros controllers; si se requiere, podríamos emitir un CustomEvent
    }
  }
}
