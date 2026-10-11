import AppKit

if CommandLine.arguments.contains("--nws-integration-fixture") {
  Task { exit(await ForecastIntegration.run()) }
  RunLoop.main.run()
} else if CommandLine.arguments.contains("--map-integration-fixture") {
  Task { @MainActor in exit(await MapIntegration.run()) }
  RunLoop.main.run()
} else {
  let application = NSApplication.shared
  let delegate = ApplicationDelegate()
  application.delegate = delegate
  application.run()
}
