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
    event.stopPropagation()
    const toggleBtn = event.currentTarget
    const node = toggleBtn.closest('.location-node')
    const children = node.querySelector(':scope > .location-children')

    if (!children) return

    const isExpanded = toggleBtn.dataset.expanded === 'true'
    const icon = toggleBtn.querySelector('i')

    if (isExpanded) {
      children.classList.add('collapsed')
      toggleBtn.dataset.expanded = 'false'
      if (icon) {
        icon.classList.remove('fa-chevron-down')
        icon.classList.add('fa-chevron-right')
      }
    } else {
      children.classList.remove('collapsed')
      toggleBtn.dataset.expanded = 'true'
      if (icon) {
        icon.classList.remove('fa-chevron-right')
        icon.classList.add('fa-chevron-down')
      }
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
      if (icon) {
        icon.classList.remove('fa-chevron-right')
        icon.classList.add('fa-chevron-down')
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
      if (icon) {
        icon.classList.remove('fa-chevron-down')
        icon.classList.add('fa-chevron-right')
      }
    })
  }
}
