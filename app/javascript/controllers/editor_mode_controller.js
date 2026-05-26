import { Controller } from "@hotwired/stimulus"

// Toggles between the Trix WYSIWYG editor and the raw HTML textarea
// in the admin post form. Both inputs remain in the DOM; the backend
// uses body_html_raw whenever it's non-empty (overrides the Trix body),
// so showing only one at a time prevents the author from accidentally
// authoring in both at the same time.
export default class extends Controller {
  static targets = ["wysiwygRadio", "htmlRadio", "wysiwygPane", "htmlPane"]

  connect() {
    // On edit forms, if the post already has body content visible in
    // Trix, default to WYSIWYG. body_html_raw is a virtual attribute,
    // never persisted, so we can't auto-detect "HTML mode was last
    // used" — author re-picks each session.
    this.switch()
  }

  switch() {
    const htmlMode = this.htmlRadioTarget.checked
    this.wysiwygPaneTarget.hidden = htmlMode
    this.htmlPaneTarget.hidden = !htmlMode
  }
}
