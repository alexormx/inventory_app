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
    await this.init()
  }

  async init() {
    const type = this.typeValue || this.element.dataset.chartType
    try {
      const x = this.xValue ? JSON.parse(this.xValue) : (this.element.dataset.chartX ? JSON.parse(this.element.dataset.chartX) : [])
      const series = this.seriesValue ? JSON.parse(this.seriesValue) : (this.element.dataset.chartSeries ? JSON.parse(this.element.dataset.chartSeries) : [])
      const data = this.dataValue ? JSON.parse(this.dataValue) : (this.element.dataset.chartData ? JSON.parse(this.element.dataset.chartData) : [])

    let chart
      switch (type) {
        case 'line':
      chart = await initLine(this.element, { x, series })
          break
        case 'bar':
      chart = await initBar(this.element, { x, series })
          break
        case 'pie':
      chart = await initPie(this.element, { series })
          break
        case 'spark':
        case 'sparkline':
      chart = await initSparkline(this.element, { data })
          break
        default:
      chart = await initLine(this.element, { x, series })
      }
      registerResizeObserver(this.element, chart)
    } catch (e) {
      console.error('chart_controller init error', e)
    }
  }
}
