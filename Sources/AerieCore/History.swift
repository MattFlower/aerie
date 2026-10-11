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
  public let sampleCounts: [String: Int]?
  public init(date: Date, values: [String: Double], sampleCounts: [String: Int]? = nil) {
    self.date = date
    self.values = values
    self.sampleCounts = sampleCounts
  }
}

/// Retains one second-resolution window and bounded minute/hour aggregates.
public struct HistoryStore {
  public private(set) var recent = RingBuffer<HistoryPoint>(capacity: 600)
  public private(set) var minutes = RingBuffer<HistoryPoint>(capacity: 1440)
  public private(set) var hours = RingBuffer<HistoryPoint>(capacity: 168)
  private var lastDate: Date?
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
  /// Changing an aggregate's source scope invalidates that series, while preserving unrelated metrics.
  public mutating func removeMetrics(_ keys: Set<String>) {
    func cleaned(_ ring: RingBuffer<HistoryPoint>) -> RingBuffer<HistoryPoint> {
      var result = RingBuffer<HistoryPoint>(capacity: ring.capacity)
      for point in ring.values {
        result.append(
          HistoryPoint(
            date: point.date, values: point.values.filter { !keys.contains($0.key) },
            sampleCounts: point.sampleCounts?.filter { !keys.contains($0.key) }))
      }
      return result
    }
    recent = cleaned(recent); minutes = cleaned(minutes); hours = cleaned(hours)
    for key in keys {
      minuteSums.removeValue(forKey: key); minuteCounts.removeValue(forKey: key)
      hourSums.removeValue(forKey: key); hourCounts.removeValue(forKey: key)
    }
  }
  public mutating func append(_ reading: HistoryPoint) {
    let timestamp = reading.date.timeIntervalSince1970
    guard timestamp.isFinite, abs(timestamp) < 1e12 else { return }
    if let lastDate, reading.date <= lastDate {
      recent = RingBuffer<HistoryPoint>(capacity: recent.capacity)
      minutes = RingBuffer<HistoryPoint>(capacity: 1440);
      hours = RingBuffer<HistoryPoint>(capacity: 168)
      minuteBucket = nil; hourBucket = nil
      minuteSums.removeAll(); minuteCounts.removeAll(); hourSums.removeAll(); hourCounts.removeAll()
    }
    let values = reading.values.filter { $0.value.isFinite }
    let point = HistoryPoint(date: reading.date, values: values)
    lastDate = reading.date
    let minute = Int(floor(point.date.timeIntervalSince1970 / 60))
    let hour = minute / 60
    if let old = minuteBucket, old != minute {
      minutes.append(
        HistoryPoint(
          date: Date(timeIntervalSince1970: Double(old * 60)),
          values: minuteSums.mapValues { $0 }.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value / Double(minuteCounts[pair.key] ?? 1)
          }, sampleCounts: minuteCounts))
      minuteSums.removeAll(keepingCapacity: true)
      minuteCounts.removeAll(keepingCapacity: true)
    }
    if let old = hourBucket, old != hour {
      hours.append(
        HistoryPoint(
          date: Date(timeIntervalSince1970: Double(old * 3600)),
          values: hourSums.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value / Double(hourCounts[pair.key] ?? 1)
          }, sampleCounts: hourCounts))
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

extension HistoryStore {
  /// Preserve pending sums/counts, so restarting neither loses nor double-counts a partial bucket.
  public func checkpoint(interval: Double, networkSelection: NetworkSelection, now: Date) throws
    -> HistoryCheckpoint
  {
    func points(_ values: [HistoryPoint], age: Double) -> [HistoryPoint] {
      values.filter { now.timeIntervalSince($0.date) <= age }.map {
        let values = $0.values.filter { HistoryCheckpoint.keys.contains($0.key) }
        return HistoryPoint(
          date: $0.date, values: values,
          sampleCounts: $0.sampleCounts?.filter { values[$0.key] != nil })
      }
    }
    func accumulator(_ bucket: Int?, sums: [String: Double], counts: [String: Int], age: Double)
      -> HistoryAccumulator
    {
      guard let lastDate, now.timeIntervalSince(lastDate) <= age else {
        return HistoryAccumulator(bucket: nil, sums: [:], counts: [:])
      }
      let sums = sums.filter { HistoryCheckpoint.keys.contains($0.key) && $0.value.isFinite }
      return HistoryAccumulator(
        bucket: bucket, sums: sums, counts: counts.filter { sums[$0.key] != nil })
    }
    let value = HistoryCheckpoint(
      schema: 1, interval: interval, savedAt: now, lastDate: lastDate,
      networkInterfaces: networkSelection.names, recent: points(recent.values, age: 600),
      minutes: points(minutes.values, age: 86_400), hours: points(hours.values, age: 604_800),
      minute: accumulator(minuteBucket, sums: minuteSums, counts: minuteCounts, age: 86_400),
      hour: accumulator(hourBucket, sums: hourSums, counts: hourCounts, age: 604_800))
    try value.validate(now: now); return value
  }
  public static func restore(
    _ checkpoint: HistoryCheckpoint, interval: Double, networkSelection: NetworkSelection, now: Date
  ) throws -> HistoryStore {
    try checkpoint.validate(now: now)
    guard [0.5, 1, 2, 3, 5].contains(interval), networkSelection.valid else {
      throw HistoryArchiveError.invalid
    }
    var result = HistoryStore(interval: interval)
    for point in checkpoint.recent.filter({ now.timeIntervalSince($0.date) <= 600 }).suffix(
      result.recent.capacity)
    { result.recent.append(point) }
    for point in checkpoint.minutes where now.timeIntervalSince(point.date) <= 86_400 {
      result.minutes.append(point)
    }
    for point in checkpoint.hours where now.timeIntervalSince(point.date) <= 604_800 {
      result.hours.append(point)
    }
    result.lastDate = checkpoint.lastDate
    if let last = checkpoint.lastDate, now.timeIntervalSince(last) <= 86_400 {
      result.minuteBucket = checkpoint.minute.bucket; result.minuteSums = checkpoint.minute.sums;
      result.minuteCounts = checkpoint.minute.counts
    }
    if let last = checkpoint.lastDate, now.timeIntervalSince(last) <= 604_800 {
      result.hourBucket = checkpoint.hour.bucket; result.hourSums = checkpoint.hour.sums;
      result.hourCounts = checkpoint.hour.counts
    }
    if NetworkSelection(names: checkpoint.networkInterfaces) != networkSelection {
      result.removeMetrics(["download", "upload"])
    }
    return result
  }
}
