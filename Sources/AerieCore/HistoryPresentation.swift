import Foundation

public struct HistoryPlotSample: Equatable {
  public let fraction: Double
  public let value: Double?
  public let startsSegment: Bool
}
public enum HistoryPlot {
  public static func samples(_ points: [HistoryPoint], metric: String, expectedInterval: Double)
    -> [HistoryPlotSample]
  {
    guard let first = points.first, let last = points.last else { return [] }
    let span = last.date.timeIntervalSince(first.date)
    guard span.isFinite, span >= 0 else { return [] }
    var previous: HistoryPoint?
    var connected = false
    return points.map { point in
      let value = point.values[metric].flatMap { $0.isFinite ? $0 : nil }
      let delta = previous.map { point.date.timeIntervalSince($0.date) }
      let gap = delta.map { $0 <= 0 || $0 > max(0.5, expectedInterval) * 3 } ?? true
      let result = HistoryPlotSample(
        fraction: span > 0 ? max(0, min(1, point.date.timeIntervalSince(first.date) / span)) : 1,
        value: value, startsSegment: !connected || gap)
      previous = point; connected = value != nil
      return result
    }
  }
  public static func nearest(_ points: [HistoryPoint], fraction: Double) -> HistoryPoint? {
    guard fraction.isFinite, let first = points.first, let last = points.last else { return nil }
    let target = first.date.addingTimeInterval(
      max(0, min(1, fraction)) * last.date.timeIntervalSince(first.date))
    return points.min {
      abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
    }
  }
}

/// Local export contains only retained numeric system series, dates, sample counts and the aggregate scope.
public enum HistoryCSV {
  private static let metrics: [(String, String)] = [
    ("cpu", "cpu_percent"), ("gpu", "gpu_percent"), ("memory", "memory_percent"),
    ("battery", "battery_percent"), ("temperature", "maximum_temperature_celsius"),
    ("diskFree", "first_volume_free_gib"), ("download", "download_bytes_per_second"),
    ("upload", "upload_bytes_per_second"), ("diskRead", "disk_read_bytes_per_second"),
    ("diskWrite", "disk_write_bytes_per_second"), ("thermal", "thermal_state_ordinal"),
  ]
  public static func data(points: [HistoryPoint], resolutionSeconds: Double, aggregateScope: String)
    -> Data
  {
    let formatter = ISO8601DateFormatter();
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    func cell(_ value: String) -> String {
      "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    var lines = [
      (["date_utc", "resolution_seconds", "network_scope"]
        + metrics.flatMap { [$0.1, $0.1 + "_samples"] }).joined(separator: ",")
    ]
    for point in points where point.date.timeIntervalSince1970.isFinite {
      var fields = [
        formatter.string(from: point.date),
        resolutionSeconds.isFinite ? String(resolutionSeconds) : "", cell(aggregateScope),
      ]
      for (key, _) in metrics {
        let value = point.values[key].flatMap { $0.isFinite ? $0 : nil }
        fields.append(value.map { String($0) } ?? "")
        fields.append(
          value.flatMap { _ in (point.sampleCounts?[key] ?? (resolutionSeconds < 60 ? 1 : nil)) }
            .map { String($0) } ?? "")
      }
      lines.append(fields.joined(separator: ","))
    }
    return Data((lines.joined(separator: "\n") + "\n").utf8)
  }
}

/// Select a time window using actual timestamps; gaps and missing readings stay unchanged.
public enum HistoryWindow {
  public static func visible(_ points: [HistoryPoint], zoom: Double, position: Double)
    -> [HistoryPoint]
  {
    guard zoom.isFinite, (1...64).contains(zoom), position.isFinite, (0...1).contains(position),
      let first = points.first, let last = points.last
    else { return [] }
    let span = last.date.timeIntervalSince(first.date)
    guard span.isFinite, span >= 0 else { return [] }
    if zoom == 1 || span == 0 { return points }
    let width = span / zoom
    let start = first.date.addingTimeInterval((span - width) * position)
    let end = start.addingTimeInterval(width)
    return points.filter { $0.date >= start && $0.date <= end }
  }
}
