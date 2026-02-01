import { Controller } from "@hotwired/stimulus"

// Controls the inventory locations tree view with expand/collapse functionality
export default class extends Controller {
  connect() {
    // Initialize all nodes as expanded
    this.element.querySelectorAll('.location-toggle').forEach(toggle => {
      toggle.dataset.expanded = 'true'
    })
  }

  // Toggle a single node's children visibility
  toggle(event) {
    const toggleBtn = event.currentTarget
    const node = toggleBtn.closest('.location-node')
    const children = node.querySelector('.location-children')

    if (!children) return

    const isExpanded = toggleBtn.dataset.expanded === 'true'

    if (isExpanded) {
      children.classList.add('collapsed')
      toggleBtn.dataset.expanded = 'false'
      toggleBtn.querySelector('i').classList.replace('bi-chevron-down', 'bi-chevron-right')
    } else {
      children.classList.remove('collapsed')
      toggleBtn.dataset.expanded = 'true'
      toggleBtn.querySelector('i').classList.replace('bi-chevron-right', 'bi-chevron-down')
    }
  }

  // Expand all nodes
  expandAll() {
    this.element.querySelectorAll('.location-children').forEach(children => {
      children.classList.remove('collapsed')
    })
    this.element.querySelectorAll('.location-toggle').forEach(toggle => {
      toggle.dataset.expanded = 'true'
      const icon = toggle.querySelector('i')
      if (icon && icon.classList.contains('bi-chevron-right')) {
        icon.classList.replace('bi-chevron-right', 'bi-chevron-down')
      }
    })
  }

  // Collapse all nodes
  collapseAll() {
    this.element.querySelectorAll('.location-children').forEach(children => {
      children.classList.add('collapsed')
    })
    this.element.querySelectorAll('.location-toggle').forEach(toggle => {
      toggle.dataset.expanded = 'false'
      const icon = toggle.querySelector('i')
      if (icon && icon.classList.contains('bi-chevron-down')) {
        icon.classList.replace('bi-chevron-down', 'bi-chevron-right')
      }
    })
  }
}
