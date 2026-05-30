// Separate bundle for the dashboard charting stack (echarts is ~1 MB).
// Loaded only on admin pages that render charts, so it never ships in the
// shared application.js that customers download. Runs its own Stimulus
// Application instance registering just the chart controller.
import { Application } from "@hotwired/stimulus"
import ChartController from "./controllers/chart_controller"

const application = Application.start()
application.register("chart", ChartController)
