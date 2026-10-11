import Foundation

public enum RuleComparison: String, Codable { case above, below }
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
  public var enabled = true
  public init(
    metric: String, threshold: Double, comparison: RuleComparison = .above,
    duration: Double = 30, cooldown: Double = 300
  ) {
    self.metric = metric
    self.threshold = threshold
    self.comparison = comparison
    self.duration = duration
    self.cooldown = cooldown
  }
  public var valid: Bool {
    ["cpu", "gpu", "memory", "battery", "temperature", "diskFree", "download", "upload", "thermal"]
      .contains(metric) && threshold.isFinite && threshold >= 0 && duration.isFinite
      && duration >= 0 && duration <= 86400 && cooldown.isFinite && cooldown >= 10
      && cooldown <= 604800
  }
}
public struct RuleEngine {
  private var started: [UUID: Double] = [:]
  private var lastFired: [UUID: Double] = [:]
  private var previousTime: Double?
  private var definitions: [UUID: ThresholdRule] = [:]
  public init() {}
  public mutating func evaluate(
    rules: [ThresholdRule], values: [String: Double], time: Double,
    maximumGap: Double = 30
  ) -> [ThresholdRule] {
    if let previousTime, time <= previousTime || time - previousTime > maximumGap {
      started.removeAll()
    }
    previousTime = time
    let ids = Set(rules.map(\.id))
    started = started.filter { ids.contains($0.key) }
    lastFired = lastFired.filter { ids.contains($0.key) }
    definitions = definitions.filter { ids.contains($0.key) }
    var fired: [ThresholdRule] = []
    for rule in rules {
      if let previous = definitions[rule.id], previous != rule {
        started[rule.id] = nil
        lastFired[rule.id] = nil
      }
      definitions[rule.id] = rule
      guard rule.enabled, rule.valid, let value = values[rule.metric], value.isFinite else {
        started[rule.id] = nil
        continue
      }
      let met = rule.comparison == .above ? value > rule.threshold : value < rule.threshold
      guard met else {
        started[rule.id] = nil
        continue
      }
      if started[rule.id] == nil { started[rule.id] = time }
      if time - (started[rule.id] ?? time) >= rule.duration,
        lastFired[rule.id].map({ time - $0 >= rule.cooldown }) ?? true
      {
        fired.append(rule)
        lastFired[rule.id] = time
      }
    }
    return fired
  }
  public mutating func reset() {
    started.removeAll()
    previousTime = nil
  }
}
