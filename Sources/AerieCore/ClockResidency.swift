import Foundation

public enum ClockChannelKind: Int { case cpuComplex, cpuCore, gpu }
public struct ClockCounter {
  public var kind: ClockChannelKind
  public var identity: String
  public var name: String
  public var unit: String
  public var states: [(name: String, ticks: UInt64)]
  public init(
    kind: ClockChannelKind, identity: String, name: String, unit: String,
    states: [(name: String, ticks: UInt64)]
  ) {
    self.kind = kind; self.identity = identity; self.name = name; self.unit = unit;
    self.states = states
  }
}
public struct ClockResidency {
  public var kind: ClockChannelKind
  public var name: String
  public var activeFraction: Double?
  /// Interval-weighted active clock frequency, only when every occupied active state names Hz.
  public var activeGHz: Double?
  public var states: [(name: String, fraction: Double)]
}
public struct ClockResidencyTracker {
  private var previous: [String: ClockCounter] = [:]
  private var time: Double?
  public init() {}
  public mutating func reset() { previous.removeAll(); time = nil }
  public mutating func update(_ counters: [ClockCounter], time now: Double) -> [ClockResidency] {
    guard now.isFinite, counters.count <= 128,
      Set(counters.map(\.identity)).count == counters.count,
      counters.allSatisfy({
        !$0.identity.isEmpty && $0.identity.utf8.count <= 192 && $0.name.utf8.count <= 64
          && $0.unit.utf8.count <= 32 && !$0.states.isEmpty && $0.states.count <= 64
          && Set($0.states.map(\.name)).count == $0.states.count
          && $0.states.allSatisfy({ !$0.name.isEmpty && $0.name.utf8.count <= 32 })
      })
    else {
      reset(); return []
    }
    let elapsed = time.map { now - $0 }
    defer {
      previous = Dictionary(uniqueKeysWithValues: counters.map { ($0.identity, $0) }); time = now
    }
    return counters.map { counter in
      var result = ClockResidency(
        kind: counter.kind, name: counter.name,
        activeFraction: nil, activeGHz: nil, states: [])
      guard let elapsed, elapsed > 0, elapsed <= 30,
        let old = previous[counter.identity], old.kind == counter.kind,
        old.name == counter.name, old.unit == counter.unit,
        old.states.map(\.name) == counter.states.map(\.name)
      else { return result }
      var deltas: [UInt64] = [], total: UInt64 = 0
      for (before, after) in zip(old.states, counter.states) {
        guard after.ticks >= before.ticks else { return result }
        let delta = after.ticks - before.ticks
        let sum = total.addingReportingOverflow(delta)
        guard !sum.overflow else { return result }; total = sum.partialValue; deltas.append(delta)
      }
      guard total > 0 else { return result }
      result.states = zip(counter.states, deltas).map { ($0.name, Double($1) / Double(total)) }
      var active: UInt64 = 0, frequencySum = 0.0, frequencyKnown = true, classificationKnown = true
      for (state, delta) in zip(counter.states, deltas) where delta > 0 {
        switch Self.activeState(state.name) {
        case false?: break
        case true?:
          active += delta
          if let GHz = Self.namedGHz(state.name) {
            frequencySum += Double(delta) * GHz
          } else {
            frequencyKnown = false
          }
        case nil: classificationKnown = false; frequencyKnown = false
        }
      }
      let hasInactiveState = counter.states.contains { Self.activeState($0.name) == false }
      if classificationKnown && hasInactiveState {
        result.activeFraction = Double(active) / Double(total)
      }
      if frequencyKnown && classificationKnown && active > 0 {
        result.activeGHz = frequencySum / Double(active)
      }
      return result
    }
  }
  private static func activeState(_ name: String) -> Bool? {
    if ["OFF", "IDLE", "DOWN", "SLEEP", "DORMANT"].contains(name.uppercased()) { return false }
    if namedGHz(name) != nil { return true }
    let parts = name.uppercased().split(separator: "P", omittingEmptySubsequences: false)
    func digits(_ value: Substring) -> Bool {
      !value.isEmpty && value.count <= 5 && value.utf8.allSatisfy { (48...57).contains($0) }
    }
    if parts.count == 2, digits(parts[1]),
      parts[0].isEmpty || (parts[0].hasPrefix("V") && digits(parts[0].dropFirst()))
    {
      return true
    }
    return nil
  }
  private static func namedGHz(_ name: String) -> Double? {
    let parts = name.uppercased().split(whereSeparator: \.isWhitespace)
    guard parts.count == 2, let value = Double(parts[0]), value.isFinite, value > 0 else {
      return nil
    }
    let GHz: Double
    switch parts[1] {
    case "HZ": GHz = value / 1e9;
    case "KHZ": GHz = value / 1e6
    case "MHZ": GHz = value / 1e3;
    case "GHZ": GHz = value;
    default: return nil
    }
    return (0.01...20).contains(GHz) ? GHz : nil
  }
}
