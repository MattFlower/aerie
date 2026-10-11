import Foundation

public struct ProcessIdentity: Hashable, Codable {
  public var pid: Int
  public var startTime: UInt64
  public init(pid: Int, startTime: UInt64) { self.pid = pid; self.startTime = startTime }
}
public struct ProcessObservation {
  public var identity: ProcessIdentity
  public var parent: Int
  public var name: String
  public var footprint: UInt64?
  public var resident: UInt64?
  public var cpuNanoseconds: UInt64?
  public var wakeups: UInt64?
  public var error: Int?
  public init(
    pid: Int, startTime: UInt64, parent: Int = 0, name: String = "",
    footprint: UInt64? = nil, resident: UInt64? = nil,
    cpuNanoseconds: UInt64? = nil, wakeups: UInt64? = nil, error: Int? = nil
  ) {
    identity = .init(pid: pid, startTime: startTime); self.parent = parent; self.name = name
    self.footprint = footprint; self.resident = resident; self.cpuNanoseconds = cpuNanoseconds
    self.wakeups = wakeups; self.error = error
  }
}
public struct ProcessReading: Codable {
  public var timestamp: Date
  public var pid: Int
  public var startTime: UInt64
  public var parent: Int
  public var name: String
  public var footprintBytes: UInt64?
  public var residentBytes: UInt64?
  public var cpuPercent: Double?
  public var interruptWakeupsPerSecond: Double?
  public var error: Int?
  public var status: String
}
public struct ProcessSample: Codable {
  public var scenario: String
  public var timestamp: Date
  public var readings: [ProcessReading]
  public var totalFootprintBytes: UInt64?
  public var totalCPUPercent: Double?
  public var totalWakeupsPerSecond: Double?
  public var footprintComplete: Bool
  public var cpuComplete: Bool
  public var wakeupsComplete: Bool
  public var incomplete: Bool
  enum CodingKeys: String, CodingKey {
    case scenario, timestamp, readings, totalFootprintBytes, totalCPUPercent, totalWakeupsPerSecond
    case footprintComplete, cpuComplete, wakeupsComplete, incomplete
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(scenario, forKey: .scenario); try c.encode(timestamp, forKey: .timestamp)
    try c.encode(readings, forKey: .readings)
    try c.encode(totalFootprintBytes, forKey: .totalFootprintBytes)
    try c.encode(totalCPUPercent, forKey: .totalCPUPercent)
    try c.encode(totalWakeupsPerSecond, forKey: .totalWakeupsPerSecond)
    try c.encode(footprintComplete, forKey: .footprintComplete)
    try c.encode(cpuComplete, forKey: .cpuComplete);
    try c.encode(wakeupsComplete, forKey: .wakeupsComplete)
    try c.encode(incomplete, forKey: .incomplete)
  }
}

/// Retains every observed identity, including exited/reparented descendants.
/// A reused PID never inherits a previous process's membership or rate baseline.
public struct ProcessSampler {
  private let selected: Set<Int>
  private var tracked: [ProcessIdentity: ProcessObservation] = [:]
  private var resolvedSeeds: Set<Int> = []
  private var previous: [ProcessIdentity: ProcessObservation] = [:]
  private var previousTime: Double?
  public init(pids: [Int]) { selected = Set(pids) }
  public mutating func sample(
    observations: [ProcessObservation], monotonicTime: Double,
    date: Date, scenario: String
  ) -> ProcessSample {
    let current = Dictionary(
      observations.map { ($0.identity, $0) }, uniquingKeysWith: { _, last in last })
    for pid in selected where !resolvedSeeds.contains(pid) {
      if let observation = observations.first(where: { $0.identity.pid == pid }) {
        tracked[observation.identity] = observation
        if observation.identity.startTime != 0 { resolvedSeeds.insert(pid) }
        // Resolve an initially unreadable identity without counting it twice.
        if observation.identity.startTime != 0 {
          tracked.removeValue(forKey: .init(pid: pid, startTime: 0))
        }
      } else {
        let missing = ProcessObservation(pid: pid, startTime: 0, error: 3)
        tracked[missing.identity] = missing
      }
    }
    var added = true
    while added {
      added = false
      let liveParentPIDs = Set(tracked.keys.filter { current[$0] != nil }.map(\.pid))
      for observation in observations where liveParentPIDs.contains(observation.parent) {
        if tracked[observation.identity] == nil {
          tracked[observation.identity] = observation; added = true
        }
      }
    }
    let dt = previousTime.map { monotonicTime - $0 } ?? 0
    var readings: [ProcessReading] = []
    for identity in tracked.keys.sorted(by: {
      $0.pid == $1.pid ? $0.startTime < $1.startTime : $0.pid < $1.pid
    }) {
      let old = previous[identity]
      let live = current[identity]
      let observation = live ?? tracked[identity]!
      func rate(_ value: UInt64?, _ prior: UInt64?) -> Double? {
        guard live != nil, let value, let prior, value >= prior, dt > 0 else { return nil }
        return Double(value - prior) / dt
      }
      let present = live != nil
      readings.append(
        ProcessReading(
          timestamp: date, pid: identity.pid, startTime: identity.startTime,
          parent: observation.parent, name: observation.name,
          footprintBytes: present ? observation.footprint : nil,
          residentBytes: present ? observation.resident : nil,
          cpuPercent: rate(observation.cpuNanoseconds, old?.cpuNanoseconds).map { $0 / 1e7 },
          interruptWakeupsPerSecond: rate(observation.wakeups, old?.wakeups),
          error: present ? observation.error : 3,
          status: !present
            ? "exited-or-unavailable" : observation.error != nil ? "unreadable" : "live"))
      if let live { tracked[identity] = live }
    }
    previous = current; previousTime = monotonicTime
    let footprintComplete = readings.allSatisfy { $0.footprintBytes != nil }
    let cpuComplete = readings.allSatisfy { $0.cpuPercent != nil }
    let wakeupsComplete = readings.allSatisfy { $0.interruptWakeupsPerSecond != nil }
    return ProcessSample(
      scenario: scenario, timestamp: date, readings: readings,
      totalFootprintBytes: footprintComplete
        ? readings.reduce(0) { $0 + ($1.footprintBytes ?? 0) } : nil,
      totalCPUPercent: cpuComplete ? readings.reduce(0) { $0 + ($1.cpuPercent ?? 0) } : nil,
      totalWakeupsPerSecond: wakeupsComplete
        ? readings.reduce(0) { $0 + ($1.interruptWakeupsPerSecond ?? 0) } : nil,
      footprintComplete: footprintComplete, cpuComplete: cpuComplete,
      wakeupsComplete: wakeupsComplete,
      incomplete: !footprintComplete || !cpuComplete || !wakeupsComplete)
  }
}
