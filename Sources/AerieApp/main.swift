import AppKit

if let index = CommandLine.arguments.firstIndex(of: "--history-archive-path"),
  index + 1 >= CommandLine.arguments.count || !CommandLine.arguments[index + 1].hasPrefix("/")
{
  fputs("--history-archive-path requires an explicit absolute local file path.\n", stderr); exit(2)
}

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
