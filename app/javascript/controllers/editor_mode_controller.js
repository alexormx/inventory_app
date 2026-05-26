import { Controller } from "@hotwired/stimulus"

// Toggles between the Trix WYSIWYG editor and the raw HTML textarea
// in the admin post form, AND keeps the persisted `post[editor_mode]`
// hidden field in sync so the choice survives reload.
//
// The backend only honors body_html_raw when editor_mode == 'html',
// so flipping the radio is safe: changing to WYSIWYG won't overwrite
// the body with any stale content sitting in the textarea, and
// changing to HTML won't lose the Trix output (it's still there if
// the author switches back).
export default class extends Controller {
  static targets = ["wysiwygRadio", "htmlRadio", "wysiwygPane", "htmlPane", "modeInput"]

  connect() {
    this.switch()
  }

  switch() {
    const htmlMode = this.htmlRadioTarget.checked
    this.wysiwygPaneTarget.hidden = htmlMode
    this.htmlPaneTarget.hidden = !htmlMode
    if (this.hasModeInputTarget) {
      this.modeInputTarget.value = htmlMode ? "html" : "wysiwyg"
    }
  }
}
