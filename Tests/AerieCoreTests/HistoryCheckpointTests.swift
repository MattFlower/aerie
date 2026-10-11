import Foundation
import XCTest
@testable import AerieCore

final class HistoryCheckpointTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 7200)
  func testRestartPreservesPartialBucketCountsWithoutLosingOrDoubleCounting() throws {
    var original = HistoryStore()
    original.append(
      .init(
        date: now.addingTimeInterval(1), values: ["cpu": 10, "download": 100, "private-name": 999]))
    original.append(.init(date: now.addingTimeInterval(2), values: ["cpu": 30]))
    let checkpoint = try original.checkpoint(
      interval: 1, networkSelection: .init(), now: now.addingTimeInterval(3))
    let data = try checkpoint.data()
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private-name"))
    var restored = try HistoryStore.restore(
      HistoryCheckpoint.decode(data, now: now.addingTimeInterval(3)), interval: 1,
      networkSelection: .init(), now: now.addingTimeInterval(3))
    restored.append(.init(date: now.addingTimeInterval(61), values: ["cpu": 50]))
    XCTAssertEqual(restored.minutes.values[0].values["cpu"], 20)
    XCTAssertEqual(restored.minutes.values[0].sampleCounts?["cpu"], 2)
    XCTAssertEqual(restored.minutes.values[0].sampleCounts?["download"], 1)
    restored.append(.init(date: now.addingTimeInterval(3601), values: ["cpu": 70]))
    XCTAssertEqual(restored.hours.values[0].values["cpu"], 30)
    XCTAssertEqual(restored.hours.values[0].sampleCounts?["cpu"], 3)
  }
  func testRestoreTrimsElapsedRetentionResizesCadenceAndInvalidatesOnlyChangedNetworkScope() throws
  {
    var store = HistoryStore(interval: 0.5)
    for i in 0..<1500 {
      store.append(
        .init(date: now.addingTimeInterval(Double(i) / 2), values: ["cpu": 10, "download": 100]))
    }
    let checkpoint = try store.checkpoint(
      interval: 0.5, networkSelection: .init(names: ["en9"]), now: now.addingTimeInterval(750))
    let restored = try HistoryStore.restore(
      checkpoint, interval: 5, networkSelection: .init(names: ["en8"]),
      now: now.addingTimeInterval(800))
    XCTAssertEqual(restored.recent.count, 120)
    XCTAssertTrue(
      restored.recent.values.allSatisfy { $0.values["download"] == nil && $0.values["cpu"] == 10 })
    XCTAssertTrue(restored.minutes.values.allSatisfy { $0.values["download"] == nil })
    let expired = try HistoryStore.restore(
      checkpoint, interval: 1, networkSelection: .init(), now: now.addingTimeInterval(700_000))
    XCTAssertEqual(expired.recent.count, 0); XCTAssertEqual(expired.minutes.count, 0);
    XCTAssertEqual(expired.hours.count, 0)
    var empty = expired;
    empty.append(.init(date: now.addingTimeInterval(700_001), values: ["cpu": 20]))
    XCTAssertEqual(empty.minutes.count, 0); XCTAssertEqual(empty.hours.count, 0)
  }
  func testOversizeFutureSchemaUnknownMetricsAndForgedCountsAreRejected() throws {
    var store = HistoryStore(); store.append(.init(date: now, values: ["cpu": 10]))
    let data = try store.checkpoint(interval: 1, networkSelection: .init(), now: now).data()
    XCTAssertThrowsError(
      try HistoryCheckpoint.decode(Data(repeating: 32, count: 2_000_001), now: now))
    XCTAssertThrowsError(try HistoryCheckpoint.decode(data, now: now.addingTimeInterval(-60)))
    for mutation in ["schema", "metric", "count"] {
      var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
      if mutation == "schema" { object["schema"] = 99 }
      if mutation == "metric" {
        var recent = object["recent"] as! [[String: Any]]; recent[0]["values"] = ["secret": 1];
        object["recent"] = recent
      }
      if mutation == "count" {
        var minute = object["minute"] as! [String: Any]; minute["counts"] = ["cpu": 0];
        object["minute"] = minute
      }
      XCTAssertThrowsError(
        try HistoryCheckpoint.decode(JSONSerialization.data(withJSONObject: object), now: now))
    }
  }
  func testLegacySettingsLeavePersistenceOffAndBackwardClockResetsRestoredHistory() throws {
    let legacy = try JSONEncoder().encode(Settings())
    XCTAssertFalse(try JSONDecoder().decode(Settings.self, from: legacy).effectivePersistentHistory)
    var store = HistoryStore(); store.append(.init(date: now, values: ["cpu": 10]))
    let checkpoint = try store.checkpoint(interval: 1, networkSelection: .init(), now: now)
    var restored = try HistoryStore.restore(
      checkpoint, interval: 1, networkSelection: .init(), now: now)
    restored.append(.init(date: now.addingTimeInterval(-1), values: ["cpu": 20]))
    XCTAssertEqual(restored.recent.count, 1);
    XCTAssertEqual(restored.recent.values[0].values["cpu"], 20)
  }
}
