import Foundation

/// Fixed capacity storage; sustained monitoring never accumulates an unbounded array.
public struct RingBuffer<Element> {
  private var storage: [Element?]
  private var next = 0
  public private(set) var count = 0
  public var capacity: Int { storage.count }
  public init(capacity: Int) { storage = Array(repeating: nil, count: max(1, capacity)) }
  public mutating func append(_ value: Element) {
    storage[next] = value
    next = (next + 1) % storage.count
    count = min(count + 1, storage.count)
  }
  public var values: [Element] {
    let start = count == storage.count ? next : 0
    return (0..<count).compactMap { storage[(start + $0) % storage.count] }
  }
  public func suffix(_ maximum: Int) -> [Element] {
    let length = min(count, max(0, maximum))
    let start = (next - length + storage.count) % storage.count
    return (0..<length).compactMap { storage[(start + $0) % storage.count] }
  }
}

public struct CounterSample: Equatable {
  public var time: Double
  public var value: UInt64
  public init(time: Double, value: UInt64) {
    self.time = time
    self.value = value
  }
}

public enum CounterRate {
  /// A reset, non-monotonic clock, or long sleep has no meaningful rate.
  public static func rate(
    previous: CounterSample?, current: CounterSample,
    maximumGap: Double = 30
  ) -> Double? {
    guard let previous, current.time > previous.time,
      current.time - previous.time <= maximumGap,
      current.value >= previous.value
    else { return nil }
    return Double(current.value - previous.value) / (current.time - previous.time)
  }
}

public struct HistoryPoint: Codable {
  public let date: Date
  public let values: [String: Double]
  public init(date: Date, values: [String: Double]) {
    self.date = date
    self.values = values
  }
}

/// Retains one second-resolution window and bounded minute/hour aggregates.
public struct HistoryStore {
  public private(set) var recent = RingBuffer<HistoryPoint>(capacity: 600)
  public private(set) var minutes = RingBuffer<HistoryPoint>(capacity: 1440)
  public private(set) var hours = RingBuffer<HistoryPoint>(capacity: 168)
  private var minuteBucket: Int?
  private var hourBucket: Int?
  private var minuteSums: [String: Double] = [:]
  private var minuteCounts: [String: Int] = [:]
  private var hourSums: [String: Double] = [:]
  private var hourCounts: [String: Int] = [:]
  public init(interval: Double = 1) {
    recent = RingBuffer<HistoryPoint>(capacity: max(1, Int(600 / max(0.5, interval))))
  }
  public mutating func configure(interval: Double) {
    let values = recent.values
    recent = RingBuffer<HistoryPoint>(capacity: max(1, Int(600 / max(0.5, interval))))
    for value in values.suffix(recent.capacity) { recent.append(value) }
  }
  public mutating func append(_ point: HistoryPoint) {
    let minute = Int(point.date.timeIntervalSince1970 / 60)
    let hour = minute / 60
    if let old = minuteBucket, old != minute {
      minutes.append(
        HistoryPoint(
          date: Date(timeIntervalSince1970: Double(old * 60)),
          values: minuteSums.mapValues { $0 }.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value / Double(minuteCounts[pair.key] ?? 1)
          }))
      minuteSums.removeAll(keepingCapacity: true)
      minuteCounts.removeAll(keepingCapacity: true)
    }
    if let old = hourBucket, old != hour {
      hours.append(
        HistoryPoint(
          date: Date(timeIntervalSince1970: Double(old * 3600)),
          values: hourSums.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value / Double(hourCounts[pair.key] ?? 1)
          }))
      hourSums.removeAll(keepingCapacity: true)
      hourCounts.removeAll(keepingCapacity: true)
    }
    minuteBucket = minute
    hourBucket = hour
    for (key, value) in point.values where value.isFinite {
      minuteSums[key, default: 0] += value
      minuteCounts[key, default: 0] += 1
      hourSums[key, default: 0] += value
      hourCounts[key, default: 0] += 1
    }
    recent.append(point)
  }
  public func points(window: Int) -> [HistoryPoint] {
    window == 0 ? recent.values : window == 1 ? minutes.values : hours.values
  }
}
