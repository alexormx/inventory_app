// Minimal ECharts helpers and theme for the dashboard
// Receives echarts as parameter for dynamic import

const baseTextColor = getComputedStyle(document.documentElement).getPropertyValue('--bs-body-color') || '#212529'
const gridLineColor = '#e9ecef'

export function applyTheme(chart) {
  if (!chart) return
  // Placeholder for theme-wide options per instance
}

function baseGrid() {
  return { left: 8, right: 8, top: 24, bottom: 8, containLabel: true }
}

export function initLine(echarts, el, { x = [], series = [] } = {}) {
  const chart = echarts.init(el)
  chart.setOption({
    textStyle: { color: baseTextColor, fontFamily: 'system-ui, "Segoe UI", Roboto, "Helvetica Neue", Arial' },
    tooltip: { trigger: 'axis' },
    grid: baseGrid(),
    xAxis: { type: 'category', data: x, axisLine: { lineStyle: { color: gridLineColor } }, axisTick: { show: false } },
    yAxis: { type: 'value', axisLine: { show: false }, splitLine: { lineStyle: { color: gridLineColor } } },
    series: series.map(s => ({ ...s, type: 'line', smooth: true, symbol: 'none' }))
  })
  applyTheme(chart)
  return chart
}

export function initBar(echarts, el, { x = [], series = [] } = {}) {
  const chart = echarts.init(el)
  chart.setOption({
    textStyle: { color: baseTextColor },
    tooltip: { trigger: 'axis' },
    grid: baseGrid(),
    xAxis: { type: 'category', data: x, axisLine: { lineStyle: { color: gridLineColor } }, axisTick: { show: false } },
    yAxis: { type: 'value', axisLine: { show: false }, splitLine: { lineStyle: { color: gridLineColor } } },
    series: series.map(s => ({ ...s, type: 'bar', barMaxWidth: 28, itemStyle: s.itemStyle || {} }))
  })
  applyTheme(chart)
  return chart
}

export function initPie(echarts, el, { series = [] } = {}) {
  const chart = echarts.init(el)
  chart.setOption({
    textStyle: { color: baseTextColor },
    tooltip: { trigger: 'item' },
    series: [
      {
        type: 'pie',
        radius: ['40%', '70%'],
        avoidLabelOverlap: true,
        itemStyle: { borderRadius: 6, borderColor: '#fff', borderWidth: 2 },
        label: { show: false },
        emphasis: { label: { show: true, fontSize: 12, fontWeight: 'bold' } },
        labelLine: { show: false },
        data: series
      }
    ]
  })
  applyTheme(chart)
  return chart
}

export function initSparkline(echarts, el, { data = [] } = {}) {
  const chart = echarts.init(el)
  chart.setOption({
    grid: { left: 0, right: 0, top: 2, bottom: 2 },
    xAxis: { type: 'category', show: false, data: data.map((_, i) => i) },
    yAxis: { type: 'value', show: false },
    series: [{ type: 'line', data, smooth: true, symbol: 'none', lineStyle: { width: 2 } }],
    tooltip: { show: false }
  })
  return chart
}

// Single global ResizeObserver per page to avoid leaks
let _ro
const observed = new WeakSet()

export function registerResizeObserver(el, chart) {
  if (!el || !chart) return
  if (!_ro) {
    _ro = new ResizeObserver(entries => {
      for (const entry of entries) {
        const c = entry.target.__echartsInstance
        if (c) c.resize()
      }
    })
  }
  if (!observed.has(el)) {
    el.__echartsInstance = chart
    _ro.observe(el)
    observed.add(el)
  }
}
