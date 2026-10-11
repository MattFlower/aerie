import Foundation

public enum ChangeKind: String, CaseIterable, Codable {
  case connectivity, powerSource, charging, lowPower, thermal, volumes, daylightSaving, timeZone
  public var title: String {
    switch self {
    case .connectivity: return "Connection state"
    case .powerSource: return "Power source"
    case .charging: return "Battery charging state"
    case .lowPower: return "Low Power Mode"
    case .thermal: return "Thermal state"
    case .volumes: return "Mounted volumes"
    case .daylightSaving: return "Daylight saving time"
    case .timeZone: return "System time zone"
    }
  }
}

public struct ChangeRule: Codable, Equatable, Identifiable {
  public var id = UUID()
  public var kind: ChangeKind
  public var enabled = true
  public var cooldown: Double
  public init(kind: ChangeKind, cooldown: Double = 300) {
    self.kind = kind; self.cooldown = cooldown
  }
  public var valid: Bool { cooldown.isFinite && (10...604800).contains(cooldown) }
}

public struct ChangeEvent: Equatable {
  public let rule: ChangeRule
  public let previous: String
  public let current: String
}

/// A baseline is required before a change can fire. Missing readings, pause and sleep
/// never turn recovery into a fabricated state transition.
public struct ChangeRuleEngine {
  private var previous: [UUID: String] = [:]
  private var lastFired: [UUID: Double] = [:]
  private var definitions: [UUID: ChangeRule] = [:]
  private var previousTime: Double?
  public init() {}
  public mutating func evaluate(
    rules: [ChangeRule], values: [ChangeKind: String], time: Double, maximumGap: Double = 30
  ) -> [ChangeEvent] {
    guard time.isFinite else { reset(); return [] }
    if let previousTime, time <= previousTime || time - previousTime > maximumGap {
      previous.removeAll()
    }
    previousTime = time
    let ids = Set(rules.map(\.id))
    previous = previous.filter { ids.contains($0.key) }
    lastFired = lastFired.filter { ids.contains($0.key) }
    definitions = definitions.filter { ids.contains($0.key) }
    var events: [ChangeEvent] = []
    for rule in rules {
      if let old = definitions[rule.id], old != rule { previous[rule.id] = nil }
      definitions[rule.id] = rule
      guard rule.enabled, rule.valid, let value = values[rule.kind], value.count <= 4096 else {
        previous[rule.id] = nil; continue
      }
      let old = previous.updateValue(value, forKey: rule.id)
      guard let old, old != value,
        lastFired[rule.id].map({ time - $0 >= rule.cooldown }) ?? true
      else { continue }
      events.append(ChangeEvent(rule: rule, previous: old, current: value))
      lastFired[rule.id] = time
    }
    return events
  }
  public mutating func reset() { previous.removeAll(); previousTime = nil }
}
