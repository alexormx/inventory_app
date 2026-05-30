// Separate bundle for the Trix rich-text editor + Action Text (~218 KB).
// Loaded only on admin pages with an editor (e.g. the blog post form), so it
// never ships in the shared application.js. Public pages render Action Text
// content as plain HTML and don't need this JS.
import "trix"
import "@rails/actiontext"
