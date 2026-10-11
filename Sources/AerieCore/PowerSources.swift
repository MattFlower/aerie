import Foundation

public enum PowerSourceKind: String, Sendable { case internalBattery, ups, unknown }
public enum PowerInputState: String, Sendable { case ac, battery, offline, unknown }

/// Per-source capacities have compatible units only within that source. No cross-source average.
public struct PowerSourceReading: Equatable, Sendable {
  public let name: String
  public let kind: PowerSourceKind
  public let transport: String?
  public let present: Bool?
  public let input: PowerInputState
  public let charging: Bool?
  public let percent: Double?
  public let minutes: Int?
  public let voltage: Double?
  public let amperage: Double?
  public let temperature: Double?
  public var watts: Double? {
    guard let voltage, let amperage else { return nil }
    let value = voltage * amperage
    return value.isFinite ? value : nil
  }
  public init(
    name: String?, kind: PowerSourceKind, transport: String?, present: Bool?,
    input: PowerInputState, charging: Bool?, current: Double?, maximum: Double?,
    minutes: Int?, voltage: Double?, amperage: Double?, temperature: Double?
  ) {
    self.name =
      Self.text(name)
      ?? (kind == .ups ? "UPS" : kind == .internalBattery ? "Internal battery" : "Power source")
    self.kind = kind; self.transport = Self.text(transport)
    self.present = present; self.input = input; self.charging = charging
    if present == true, let current, let maximum, current.isFinite, maximum.isFinite,
      maximum > 0, current >= 0, current <= maximum
    {
      percent = current / maximum
    } else {
      percent = nil
    }
    self.minutes =
      present == true && charging != nil
      ? minutes.flatMap { (0...(Int.max / 60)).contains($0) ? $0 : nil } : nil
    self.voltage = present == true ? Self.finite(voltage).flatMap { $0 >= 0 ? $0 : nil } : nil
    self.amperage = present == true ? Self.finite(amperage) : nil
    self.temperature = present == true ? Self.finite(temperature) : nil
  }
  private static func finite(_ value: Double?) -> Double? {
    value.flatMap { $0.isFinite ? $0 : nil }
  }
  private static func text(_ value: String?) -> String? {
    guard let value else { return nil }
    let scalars = value.unicodeScalars.prefix(128).filter {
      !CharacterSet.controlCharacters.contains($0)
    }
    let text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(
      in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }
}
public struct PowerSourceInventory: Equatable, Sendable {
  public static let limit = 64
  public let sources: [PowerSourceReading]
  public let available: Bool
  public let reportedCount: Int
  public let unreadableCount: Int
  public var complete: Bool {
    available && unreadableCount == 0 && reportedCount == sources.count
  }
  public var batteries: [PowerSourceReading] {
    sources.filter { $0.kind == .internalBattery && $0.present == true }
  }
  /// Unknown/unreadable/absent/type-unknown records cannot prove a unique battery.
  public var primaryBattery: PowerSourceReading? {
    guard complete, !sources.contains(where: { $0.kind == .unknown || $0.present == nil }) else {
      return nil
    }
    let batteries = batteries
    return batteries.count == 1 ? batteries[0] : nil
  }
  public init(
    sources: [PowerSourceReading] = [], available: Bool = false, reportedCount: Int = 0,
    unreadableCount: Int = 0
  ) {
    self.sources = Array(sources.prefix(Self.limit)); self.available = available
    self.reportedCount = max(reportedCount, sources.count)
    self.unreadableCount = max(0, unreadableCount)
  }
}
