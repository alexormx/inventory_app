// ECharts helpers and theme for the admin dashboard
// All init* functions receive the echarts library, a DOM element, and a data config

const PALETTE = [
  '#3b82f6', // blue
  '#10b981', // emerald
  '#f59e0b', // amber
  '#ef4444', // red
  '#8b5cf6', // violet
  '#06b6d4', // cyan
  '#f97316', // orange
  '#ec4899', // pink
  '#14b8a6', // teal
  '#64748b'  // slate
]

function textColor() {
  try {
    return getComputedStyle(document.documentElement).getPropertyValue('--bs-body-color').trim() || '#212529'
  } catch (_) { return '#212529' }
}

const GRID_LINE = '#e9ecef'
const FONT = 'system-ui, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif'

function currencyFormatter(val) {
  if (val == null) return '—'
  const n = Number(val)
  if (isNaN(n)) return val
  return '$ ' + n.toLocaleString('es-MX', { minimumFractionDigits: 0, maximumFractionDigits: 0 })
}

function tooltipAxisFormatter(params) {
  if (!Array.isArray(params)) params = [params]
  let html = `<div style="font-size:12px"><strong>${params[0]?.axisValueLabel || ''}</strong>`
  params.forEach(p => {
    const val = currencyFormatter(p.value)
    html += `<br/>${p.marker} ${p.seriesName}: <strong>${val}</strong>`
  })
  return html + '</div>'
}

function baseLegend() {
  return {
    show: true,
    bottom: 0,
    left: 'center',
    textStyle: { color: textColor(), fontSize: 11 },
    icon: 'roundRect',
    itemWidth: 12,
    itemHeight: 8,
    itemGap: 16
  }
}

// ── LINE CHART ──
export function initLine(echarts, el, { x = [], series = [] } = {}) {
  const chart = echarts.init(el)
  chart.setOption({
    color: PALETTE,
    textStyle: { color: textColor(), fontFamily: FONT },
    tooltip: {
      trigger: 'axis',
      backgroundColor: 'rgba(255,255,255,0.96)',
      borderColor: '#e5e7eb',
      textStyle: { color: '#1f2937', fontSize: 12 },
      formatter: tooltipAxisFormatter
    },
    legend: { ...baseLegend(), bottom: 0 },
    grid: { left: 12, right: 12, top: 32, bottom: 36, containLabel: true },
    xAxis: {
      type: 'category',
      data: x,
      axisLine: { lineStyle: { color: GRID_LINE } },
      axisTick: { show: false },
      axisLabel: { color: textColor(), fontSize: 11 }
    },
    yAxis: {
      type: 'value',
      axisLine: { show: false },
      splitLine: { lineStyle: { color: GRID_LINE, type: 'dashed' } },
      axisLabel: { color: '#9ca3af', fontSize: 11, formatter: v => currencyFormatter(v) }
    },
    series: series.map(s => ({
      ...s,
      type: 'line',
      smooth: true,
      symbol: 'circle',
      symbolSize: 4,
      showSymbol: false,
      emphasis: { focus: 'series', itemStyle: { shadowBlur: 6 } },
      lineStyle: { width: 2.5 },
      areaStyle: { opacity: 0.06 }
    }))
  })
  return chart
}

// ── BAR CHART ──
export function initBar(echarts, el, { x = [], series = [], stack = false } = {}) {
  const chart = echarts.init(el)
  chart.setOption({
    color: PALETTE,
    textStyle: { color: textColor(), fontFamily: FONT },
    tooltip: {
      trigger: 'axis',
      backgroundColor: 'rgba(255,255,255,0.96)',
      borderColor: '#e5e7eb',
      textStyle: { color: '#1f2937', fontSize: 12 },
      formatter: tooltipAxisFormatter
    },
    legend: { ...baseLegend(), bottom: 0 },
    grid: { left: 12, right: 12, top: 32, bottom: 36, containLabel: true },
    xAxis: {
      type: 'category',
      data: x,
      axisLine: { lineStyle: { color: GRID_LINE } },
      axisTick: { show: false },
      axisLabel: { color: textColor(), fontSize: 11, rotate: x.length > 8 ? 30 : 0 }
    },
    yAxis: {
      type: 'value',
      axisLine: { show: false },
      splitLine: { lineStyle: { color: GRID_LINE, type: 'dashed' } },
      axisLabel: { color: '#9ca3af', fontSize: 11, formatter: v => currencyFormatter(v) }
    },
    series: series.map(s => ({
      ...s,
      type: 'bar',
      barMaxWidth: 32,
      barGap: '20%',
      stack: stack ? 'total' : undefined,
      itemStyle: { borderRadius: [3, 3, 0, 0], ...(s.itemStyle || {}) },
      emphasis: { focus: 'series' }
    }))
  })
  return chart
}

// ── PIE / DONUT CHART ──
export function initPie(echarts, el, { series = [], title = '' } = {}) {
  const chart = echarts.init(el)
  chart.setOption({
    color: PALETTE,
    textStyle: { color: textColor(), fontFamily: FONT },
    tooltip: {
      trigger: 'item',
      backgroundColor: 'rgba(255,255,255,0.96)',
      borderColor: '#e5e7eb',
      textStyle: { color: '#1f2937', fontSize: 12 },
      formatter: p => `${p.marker} ${p.name}: <strong>${p.value}</strong> (${p.percent}%)`
    },
    legend: {
      orient: 'vertical',
      right: 8,
      top: 'middle',
      textStyle: { color: textColor(), fontSize: 11 },
      icon: 'circle',
      itemWidth: 8,
      itemHeight: 8
    },
    series: [
      {
        type: 'pie',
        radius: ['42%', '72%'],
        center: ['35%', '50%'],
        avoidLabelOverlap: true,
        itemStyle: { borderRadius: 5, borderColor: '#fff', borderWidth: 2 },
        label: { show: false },
        emphasis: {
          label: { show: true, fontSize: 13, fontWeight: 'bold' },
          itemStyle: { shadowBlur: 10, shadowColor: 'rgba(0,0,0,0.15)' }
        },
        labelLine: { show: false },
        data: series
      }
    ]
  })
  return chart
}

// ── SPARKLINE ──
export function initSparkline(echarts, el, { data = [] } = {}) {
  const chart = echarts.init(el)
  const color = PALETTE[0]
  chart.setOption({
    grid: { left: 0, right: 0, top: 2, bottom: 2 },
    xAxis: { type: 'category', show: false, data: data.map((_, i) => i) },
    yAxis: { type: 'value', show: false },
    series: [{
      type: 'line',
      data,
      smooth: true,
      symbol: 'none',
      lineStyle: { width: 2, color },
      areaStyle: { color: { type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{ offset: 0, color: color + '30' }, { offset: 1, color: color + '05' }] } }
    }],
    tooltip: { show: false }
  })
  return chart
}

// ── STACKED BAR ──
export function initStackedBar(echarts, el, { x = [], series = [] } = {}) {
  return initBar(echarts, el, { x, series, stack: true })
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
        if (c) {
          try { c.resize() } catch (_) { /* disposed */ }
        }
      }
    })
  }
  if (!observed.has(el)) {
    el.__echartsInstance = chart
    _ro.observe(el)
    observed.add(el)
  }
}

export function unregisterResizeObserver(el) {
  if (!el || !_ro) return
  if (observed.has(el)) {
    _ro.unobserve(el)
    observed.delete(el)
  }
  if (el.__echartsInstance) {
    delete el.__echartsInstance
  }
}
