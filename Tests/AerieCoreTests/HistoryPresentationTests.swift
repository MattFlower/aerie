import XCTest
@testable import AerieCore

final class HistoryPresentationTests: XCTestCase {
  private func point(_ seconds: Double, _ value: Double?) -> HistoryPoint {
    .init(date: Date(timeIntervalSince1970: seconds), values: value.map { ["cpu": $0] } ?? [:])
  }
  func testPlotUsesElapsedTimeAndSeparatesSleepAndUnavailableReadings() {
    let points = [point(0, 10), point(1, 20), point(100, 30), point(101, nil), point(102, 40)]
    let samples = HistoryPlot.samples(points, metric: "cpu", expectedInterval: 1)
    XCTAssertEqual(samples.count, 5)
    XCTAssertEqual(samples[1].fraction, 1 / 102, accuracy: 0.000001)
    XCTAssertEqual(samples[2].fraction, 100 / 102, accuracy: 0.000001)
    XCTAssertEqual(samples.map(\.startsSegment), [true, false, true, false, true])
    XCTAssertNil(samples[3].value)
    XCTAssertEqual(HistoryPlot.nearest(points, fraction: 0.5)?.date.timeIntervalSince1970, 100)
    XCTAssertNil(HistoryPlot.nearest(points, fraction: .nan))
    XCTAssertTrue(HistoryPlot.samples([], metric: "cpu", expectedInterval: 1).isEmpty)
  }
  func testMinuteAndHourlyAveragesRetainObservedPerMetricCounts() {
    var history = HistoryStore()
    history.append(point(0, 20)); history.append(point(1, nil)); history.append(point(2, 40))
    history.append(point(60, nil)); history.append(point(3600, 10))
    XCTAssertEqual(history.minutes.values[0].values["cpu"], 30)
    XCTAssertEqual(history.minutes.values[0].sampleCounts?["cpu"], 2)
    XCTAssertEqual(history.hours.values[0].sampleCounts?["cpu"], 2)
    XCTAssertNil(history.recent.values[1].values["cpu"])
    XCTAssertNil(history.minutes.values[1].sampleCounts?["cpu"])
    history.removeMetrics(["cpu"])
    XCTAssertNil(history.minutes.values[0].sampleCounts?["cpu"])
  }
  func testBackwardWallClockStartsFreshBucketsAndInvalidDatesCannotCorruptHistory() {
    var history = HistoryStore(interval: 2)
    history.append(point(60, 90)); history.append(point(61, 80)); history.append(point(0, 10))
    XCTAssertEqual(history.recent.count, 1); XCTAssertEqual(history.recent.capacity, 300)
    XCTAssertEqual(history.minutes.count, 0); XCTAssertEqual(history.hours.count, 0)
    history.append(point(.nan, 10)); history.append(point(1e15, 20))
    XCTAssertEqual(history.recent.count, 1)
    history.append(point(60, nil))
    XCTAssertEqual(history.minutes.values[0].values["cpu"], 10)
    XCTAssertEqual(history.minutes.values[0].sampleCounts?["cpu"], 1)
  }
  func testCSVHasUTCUnitsMissingCellsObservedCountsAndEscapedScopeOnly() throws {
    let point = HistoryPoint(
      date: Date(timeIntervalSince1970: 0),
      values: ["cpu": 30, "download": 0, "upload": .nan, "unexported-personal-field": 999],
      sampleCounts: ["cpu": 2, "download": 1])
    let data = HistoryCSV.data(
      points: [point], resolutionSeconds: 60, aggregateScope: "Selected: en0, \"synthetic\"")
    let csv = try XCTUnwrap(String(data: data, encoding: .utf8))
    XCTAssertTrue(
      csv.contains("date_utc,resolution_seconds,network_scope,cpu_percent,cpu_percent_samples"))
    XCTAssertTrue(
      csv.contains("1970-01-01T00:00:00.000Z,60.0,\"Selected: en0, \"\"synthetic\"\"\",30.0,2,"))
    XCTAssertTrue(csv.contains("download_bytes_per_second"))
    XCTAssertFalse(csv.contains("nan")); XCTAssertFalse(csv.contains("999"));
    XCTAssertFalse(csv.contains("personal"))
    XCTAssertEqual(csv.split(separator: "\n").count, 2)
  }
  func testSyntheticSingleReadingExportAndAggregationDoNotInventCoverage() throws {
    let raw = HistoryCSV.data(
      points: [point(0, 0)], resolutionSeconds: 1, aggregateScope: "All active interfaces")
    XCTAssertTrue(String(decoding: raw, as: UTF8.self).contains(",0.0,1,"))
    let aggregate = HistoryCSV.data(
      points: [point(0, 0)], resolutionSeconds: 60, aggregateScope: "All active interfaces")
    XCTAssertTrue(String(decoding: aggregate, as: UTF8.self).contains(",0.0,,"))
    var history = HistoryStore()
    history.append(.init(date: Date(timeIntervalSince1970: 0), values: ["cpu": .infinity]))
    XCTAssertNil(history.recent.values[0].values["cpu"])
  }
}
