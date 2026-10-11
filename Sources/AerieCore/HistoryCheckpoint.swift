import Foundation

public enum HistoryArchiveError: Error { case oversized, invalid }
public struct HistoryAccumulator: Codable {
  let bucket: Int?
  let sums: [String: Double]
  let counts: [String: Int]
}
/// Versioned local numeric checkpoint. No process, sensor, volume, calendar or weather labels.
public struct HistoryCheckpoint: Codable {
  public static let maximumBytes = 2_000_000
  static let keys: Set<String> = [
    "cpu", "gpu", "memory", "battery", "temperature", "diskFree", "download", "upload", "diskRead",
    "diskWrite", "thermal",
  ]
  let schema: Int
  let interval: Double
  let savedAt: Date
  let lastDate: Date?
  let networkInterfaces: [String]?
  let recent, minutes, hours: [HistoryPoint]
  let minute, hour: HistoryAccumulator
  public func data() throws -> Data {
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .millisecondsSince1970
    let data = try encoder.encode(self)
    guard data.count <= Self.maximumBytes else { throw HistoryArchiveError.oversized }
    return data
  }
  public static func decode(_ data: Data, now: Date) throws -> HistoryCheckpoint {
    guard data.count <= maximumBytes else { throw HistoryArchiveError.oversized }
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .millisecondsSince1970
    let value = try decoder.decode(Self.self, from: data); try value.validate(now: now);
    return value
  }
  func validate(now: Date) throws {
    func validDate(_ value: Date) -> Bool {
      value.timeIntervalSince1970.isFinite && abs(value.timeIntervalSince1970) < 1e12
        && value <= now.addingTimeInterval(5)
    }
    guard schema == 1, [0.5, 1, 2, 3, 5].contains(interval), validDate(savedAt),
      NetworkSelection(names: networkInterfaces).valid,
      lastDate.map({ validDate($0) && $0 <= savedAt }) ?? true,
      recent.count <= 1200, minutes.count <= 1440, hours.count <= 168
    else { throw HistoryArchiveError.invalid }
    for (points, aggregated) in [(recent, false), (minutes, true), (hours, true)] {
      var previous: Date?
      for point in points {
        guard validDate(point.date), point.date <= (lastDate ?? savedAt),
          previous.map({ point.date > $0 }) ?? true,
          Set(point.values.keys).isSubset(of: Self.keys), point.values.values.allSatisfy(\.isFinite)
        else { throw HistoryArchiveError.invalid }
        if aggregated {
          guard let counts = point.sampleCounts, Set(counts.keys) == Set(point.values.keys),
            counts.values.allSatisfy({ (1...10_000).contains($0) })
          else { throw HistoryArchiveError.invalid }
        } else if point.sampleCounts != nil {
          throw HistoryArchiveError.invalid
        }
        previous = point.date
      }
    }
    for (accumulator, divisor) in [(minute, 60), (hour, 3600)] {
      guard Set(accumulator.sums.keys).isSubset(of: Self.keys),
        Set(accumulator.counts.keys) == Set(accumulator.sums.keys),
        accumulator.sums.values.allSatisfy(\.isFinite),
        accumulator.counts.values.allSatisfy({ (1...10_000).contains($0) })
      else { throw HistoryArchiveError.invalid }
      if let bucket = accumulator.bucket {
        guard let lastDate, bucket == Int(floor(lastDate.timeIntervalSince1970 / Double(divisor)))
        else { throw HistoryArchiveError.invalid }
      } else if !accumulator.sums.isEmpty {
        throw HistoryArchiveError.invalid
      }
    }
  }
}
