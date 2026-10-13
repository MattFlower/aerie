import AerieCore
import AppKit
import OSLog

/// Local debug events emitted only on toolbar actions. No absolute coordinates, user content,
/// system readings, background sampling, or persistent configuration are recorded.
enum MenuRoutingTrace {
  private static let logger = Logger(subsystem: "app.aerie.monitor", category: "menu-routing")
  static func pointer(
    source: String, eventType: Int, windowMatches: Bool, point: NSPoint?, bounds: NSRect,
    hit: Module?, focused: Module?
  ) {
    let inside = point.map { bounds.contains($0) } ?? false
    let fraction =
      inside && bounds.width > 0
      ? Int(((point!.x - bounds.minX) / bounds.width) * 100) : -1
    let hitName = hit?.rawValue ?? "none", focusName = focused?.rawValue ?? "none"
    logger.debug(
      "toolbar source=\(source, privacy: .public) event=\(eventType) eventWindowMatches=\(windowMatches) pointerInside=\(inside) relativeXPercent=\(fraction) hit=\(hitName, privacy: .public) focused=\(focusName, privacy: .public)"
    )
  }
  static func selection(_ requested: Module, shown: Module?) {
    let previous = shown?.rawValue ?? "none"
    logger.debug(
      "toolbar requested=\(requested.rawValue, privacy: .public) shown=\(previous, privacy: .public)"
    )
  }
  static func metrics(in rows: [DashboardRow]) -> String {
    let allowed: Set<String> = [
      "cpu", "gpu", "memory", "download", "upload", "read", "write", "battery",
    ]
    let keys = rows.flatMap { row -> [String] in
      switch row {
      case .chart(let key, _, _, _): return [key]
      case .trend(_, _, let series): return series.map(\.key)
      default: return []
      }
    }
    return keys.filter { allowed.contains($0) }.prefix(3).joined(separator: ",")
  }
  static func rendered(_ module: Module, picker: Module?, metrics: String) {
    let selected = picker?.rawValue ?? "none"
    logger.debug(
      "toolbar rendered=\(module.rawValue, privacy: .public) picker=\(selected, privacy: .public) chartMetrics=\(metrics, privacy: .public)"
    )
  }
  static func host(
    phase: String, id: Int, module: Module?, controllerMatches: Bool,
    viewAttached: Bool, visible: Bool, visibleDashboardCount: Int
  ) {
    let selected = module?.rawValue ?? "none"
    logger.debug(
      "toolbar hostPhase=\(phase, privacy: .public) hostID=\(id) module=\(selected, privacy: .public) controllerMatches=\(controllerMatches) viewAttached=\(viewAttached) visible=\(visible) visibleDashboardCount=\(visibleDashboardCount)"
    )
  }
}
