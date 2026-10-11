import Foundation

public enum RuleComparison: String, Codable, CaseIterable {
  case above, below, atLeast, atMost, inside, outside
  public var title: String {
    switch self {
    case .above: return "Above"
    case .below: return "Below"
    case .atLeast: return "At least"
    case .atMost: return "At most"
    case .inside: return "Inside range (inclusive)"
    case .outside: return "Outside range"
    }
  }
  public var requiresUpperBound: Bool { self == .inside || self == .outside }
}
public enum RuleEdits {
  public static func replacing(_ existing: ThresholdRule, with proposed: ThresholdRule)
    -> ThresholdRule
  {
    var value = proposed; value.id = existing.id; value.enabled = existing.enabled; return value
  }
}
public struct ThresholdRule: Codable, Equatable, Identifiable {
  public var id = UUID()
  public var metric: String
  public var threshold: Double
  public var comparison: RuleComparison
  public var duration: Double
  public var cooldown: Double
  public var sensorUnit: String?
  public var upperThreshold: Double?
  public var hysteresis: Double?
  public var repeatWhileMet: Bool?
  public var recoveryBand: Double { hysteresis ?? 0 }
  public var repeats: Bool { repeatWhileMet ?? true }
  public var enabled = true
  public init(
    metric: String, threshold: Double, comparison: RuleComparison = .above,
    duration: Double = 30, cooldown: Double = 300, sensorUnit: String? = nil,
    upperThreshold: Double? = nil, hysteresis: Double? = nil, repeatWhileMet: Bool? = nil
  ) {
    self.metric = metric
    self.threshold = threshold
    self.comparison = comparison
    self.duration = duration
    self.cooldown = cooldown
    self.sensorUnit = sensorUnit; self.upperThreshold = upperThreshold
    self.hysteresis = hysteresis; self.repeatWhileMet = repeatWhileMet
  }
  public var valid: Bool {
    let individual = SensorIdentity.key(metric: metric) != nil
    let validMetric =
      individual
      ? sensorUnit.map { SensorIdentity.units.contains($0) } ?? false
      : sensorUnit == nil
        && [
          "cpu", "gpu", "memory", "battery", "temperature", "diskFree", "download", "upload",
          "thermal", "diskRead", "diskWrite",
        ].contains(metric)
    let validThreshold =
      individual
      ? abs(threshold) <= 1e12 && (sensorUnit != "rpm" || threshold >= 0)
      : threshold >= 0
    let validUpper: Bool
    if comparison.requiresUpperBound {
      validUpper =
        upperThreshold.map { $0.isFinite && $0 >= threshold && (!individual || abs($0) <= 1e12) }
        ?? false
    } else {
      validUpper = upperThreshold == nil
    }
    let validBand =
      recoveryBand.isFinite && (0...1e12).contains(recoveryBand)
      && (comparison != .outside
        || upperThreshold.map { recoveryBand * 2 <= $0 - threshold } == true)
    return validUpper && validBand && validMetric && threshold.isFinite && validThreshold
      && duration.isFinite
      && duration >= 0 && duration <= 86400 && cooldown.isFinite && cooldown >= 10
      && cooldown <= 604800
  }
  /// Recovery bands apply only after a live reading enters the condition; they never arm a rule.
  public func matches(_ value: Double, active: Bool = false) -> Bool {
    guard valid, value.isFinite else { return false }
    let band = active ? recoveryBand : 0
    switch comparison {
    case .above: return value > threshold - band
    case .below: return value < threshold + band
    case .atLeast: return value >= threshold - band
    case .atMost: return value <= threshold + band
    case .inside: return value >= threshold - band && value <= (upperThreshold ?? threshold) + band
    case .outside: return value < threshold + band || value > (upperThreshold ?? threshold) - band
    }
  }
  public var conditionDescription: String {
    let unit = sensorUnit.map { " " + $0 } ?? ""
    let lower = String(format: "%g", threshold)
    let bounds = upperThreshold.map { lower + "–" + String(format: "%g", $0) } ?? lower
    return comparison.title + " " + bounds + unit
  }
  public var valueKey: String {
    SensorIdentity.key(metric: metric) != nil ? metric + ":" + (sensorUnit ?? "") : metric
  }
}
public struct RuleEngine {
  private var started: [UUID: Double] = [:]
  private var lastFired: [UUID: Double] = [:]
  private var previousTime: Double?
  private var active: Set<UUID> = []
  private var firedEpisode: Set<UUID> = []
  private var definitions: [UUID: ThresholdRule] = [:]
  public init() {}
  public mutating func evaluate(
    rules: [ThresholdRule], values: [String: Double], time: Double,
    maximumGap: Double = 30
  ) -> [ThresholdRule] {
    guard time.isFinite, maximumGap.isFinite, maximumGap >= 0 else { reset(); return [] }
    if let previousTime, time <= previousTime || time - previousTime > maximumGap {
      started.removeAll(); active.removeAll(); firedEpisode.removeAll()
    }
    previousTime = time
    let ids = Set(rules.map(\.id))
    active.formIntersection(ids); firedEpisode.formIntersection(ids)
    started = started.filter { ids.contains($0.key) }
    lastFired = lastFired.filter { ids.contains($0.key) }
    definitions = definitions.filter { ids.contains($0.key) }
    var fired: [ThresholdRule] = []
    for rule in rules {
      if let previous = definitions[rule.id], previous != rule {
        started[rule.id] = nil
        lastFired[rule.id] = nil
        active.remove(rule.id); firedEpisode.remove(rule.id)
      }
      definitions[rule.id] = rule
      guard rule.enabled, rule.valid, let value = values[rule.valueKey], value.isFinite else {
        started[rule.id] = nil; active.remove(rule.id); firedEpisode.remove(rule.id)
        continue
      }
      let met = rule.matches(value, active: active.contains(rule.id))
      guard met else {
        started[rule.id] = nil; active.remove(rule.id); firedEpisode.remove(rule.id)
        continue
      }
      active.insert(rule.id)
      if started[rule.id] == nil { started[rule.id] = time }
      if (rule.repeats || !firedEpisode.contains(rule.id)),
        time - (started[rule.id] ?? time) >= rule.duration,
        lastFired[rule.id].map({ time - $0 >= rule.cooldown }) ?? true
      {
        fired.append(rule)
        lastFired[rule.id] = time; firedEpisode.insert(rule.id)
      }
    }
    return fired
  }
  public mutating func reset() {
    started.removeAll(); active.removeAll(); firedEpisode.removeAll()
    previousTime = nil
  }
}
