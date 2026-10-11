import Foundation

public enum MapTimeline: Equatable {
  case timeless
  case frames([Date])
  case unavailable(latestAdvertised: Date?)

  public var times: [Date] { if case .frames(let times) = self { return times }; return [] }
  public var available: Bool { if case .unavailable = self { return false }; return true }
}

/// Metadata refresh reconciles by stable service name and valid time, not object equality.
public struct MapSelection {
  public private(set) var kind: WeatherMapKind = .radar
  public private(set) var layer: WMSLayer?
  public private(set) var timeline: MapTimeline = .timeless
  public private(set) var frame = 0
  public var playing = false
  public init() {}
  public var time: Date? { timeline.times.indices.contains(frame) ? timeline.times[frame] : nil }
  public mutating func select(kind: WeatherMapKind) {
    guard self.kind != kind else { return }
    self.kind = kind; layer = nil; timeline = .timeless; frame = 0; playing = false
  }
  public mutating func select(layer: WMSLayer) {
    if self.layer?.name != layer.name { timeline = .timeless; frame = 0; playing = false }
    self.layer = layer
  }
  public mutating func select(frame: Int) {
    self.frame = min(max(0, frame), max(0, timeline.times.count - 1))
  }
  public mutating func reconcile(layers: [WMSLayer], now: Date) throws {
    let previousTime = time
    let previousName = layer?.name
    let chosen = try layers.first(where: { $0.name == previousName }) ?? kind.preferred(layers)
    layer = chosen; timeline = chosen.timeline(kind: kind, now: now)
    if previousName == chosen.name, let previousTime,
      let index = timeline.times.firstIndex(of: previousTime)
    {
      frame = index
    } else {
      frame = kind.forecast ? 0 : max(0, timeline.times.count - 1)
    }
    if timeline.times.count <= 1 { playing = false }
  }
}

/// The same reducer drives the native window's timers and jobs through overlapping lifecycle events.
public struct MapActivity {
  public enum Transition: Equatable { case unchanged, suspend, resume }
  public var windowVisible = false
  public var miniaturized = false
  public var applicationHidden = false
  public var sleeping = false
  public var closed = false
  public private(set) var active = false
  public init() {}
  @discardableResult public mutating func reconcile() -> Transition {
    let next = windowVisible && !miniaturized && !applicationHidden && !sleeping && !closed
    guard next != active else { return .unchanged }
    active = next; return next ? .resume : .suspend
  }
}

/// WMS permits comma-separated instants and start/end/period intervals. Expansion is bounded.
public enum WMSTimeDimension {
  public static func parse(_ value: String, maximumCount: Int = 10000) -> [Date]? {
    guard maximumCount > 0, maximumCount <= 10000, value.count <= 256000 else { return nil }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    func date(_ text: Substring) -> Date? {
      let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
      return fractional.date(from: value) ?? plain.date(from: value)
    }
    var result = Set<Date>(); var expanded = 0
    for token in value.split(separator: ",", omittingEmptySubsequences: true) {
      let components = token.split(separator: "/", omittingEmptySubsequences: false)
      if components.count == 1, let instant = date(components[0]) {
        expanded += 1; guard expanded <= maximumCount else { return nil }; result.insert(instant)
      } else if components.count == 3, let start = date(components[0]),
        let end = date(components[1]),
        let step = duration(String(components[2]).trimmingCharacters(in: .whitespacesAndNewlines)),
        end >= start
      {
        let count = floor(end.timeIntervalSince(start) / step) + 1
        guard count.isFinite, count >= 1, count <= Double(maximumCount - expanded) else {
          return nil
        }
        for index in 0..<Int(count) {
          result.insert(start.addingTimeInterval(Double(index) * step))
        }
        expanded += Int(count)
      } else {
        // Malformed or calendar-month/year periods cannot become an undated default image.
        return nil
      }
    }
    return result.sorted()
  }
  private static func duration(_ text: String) -> Double? {
    let pattern =
      "^P(?:(\\d+(?:\\.\\d+)?)W)?(?:(\\d+(?:\\.\\d+)?)D)?(?:T(?:(\\d+(?:\\.\\d+)?)H)?(?:(\\d+(?:\\.\\d+)?)M)?(?:(\\d+(?:\\.\\d+)?)S)?)?$"
    guard text.count <= 100, let expression = try? NSRegularExpression(pattern: pattern),
      let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    else { return nil }
    let weights = [604800.0, 86400, 3600, 60, 1]
    var seconds = 0.0
    for index in 1...weights.count {
      if let range = Range(match.range(at: index), in: text), let value = Double(text[range]) {
        seconds += value * weights[index - 1]
      }
    }
    return seconds.isFinite && seconds > 0 ? seconds : nil
  }
}
