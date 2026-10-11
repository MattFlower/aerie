import XCTest
@testable import AerieCore

final class NetworkSelectionTests: XCTestCase {
  func testSelectionRejectsAmbiguityAndOnlyChangesAggregateMembership() {
    let selected = NetworkSelection(names: ["en0"])
    XCTAssertTrue(selected.valid); XCTAssertTrue(selected.includes(name: "en0", active: true))
    XCTAssertFalse(selected.includes(name: "utun1", active: true));
    XCTAssertFalse(selected.includes(name: "en0", active: false))
    XCTAssertTrue(NetworkSelection().includes(name: "utun1", active: true))
    let none = NetworkSelection(names: [])
    XCTAssertTrue(none.valid); XCTAssertFalse(none.includes(name: "en0", active: true))
    XCTAssertEqual(none.description, "No interfaces selected")
    for names in [["en0", "en0"], [""], ["invalid/name"], [String(repeating: "a", count: 32)]] {
      XCTAssertFalse(NetworkSelection(names: names).valid)
    }
    var settings = Settings(); settings.networkInterfaces = ["en0"]
    XCTAssertNoThrow(try settings.validated()); settings.networkInterfaces = [];
    XCTAssertNoThrow(try settings.validated())
  }
  func testSessionStartsAtZeroInsteadOfCreditingPrelaunchCumulativeTraffic() {
    var tracker = NetworkSessionTracker(); let date = Date(timeIntervalSince1970: 100)
    let first = tracker.update(
      [.init(name: "en0", received: 430_000_000_000, sent: 490_000_000_000)], date: date)["en0"]!
    XCTAssertEqual(first.received, 0); XCTAssertEqual(first.sent, 0); XCTAssertFalse(first.rebased)
    let next = tracker.update(
      [.init(name: "en0", received: 430_000_000_123, sent: 490_000_000_456)],
      date: date.addingTimeInterval(1))["en0"]!
    XCTAssertEqual(next.received, 123); XCTAssertEqual(next.sent, 456);
    XCTAssertEqual(next.started, date)
  }
  func testResetSourceChangeAndDisappearanceRebaseRatherThanInventTraffic() {
    var tracker = NetworkSessionTracker(); let date = Date(timeIntervalSince1970: 100)
    _ = tracker.update([.init(name: "en0", received: 100, sent: 100)], date: date)
    let reset = tracker.update(
      [.init(name: "en0", received: 10, sent: 20)], date: date.addingTimeInterval(1))["en0"]!
    XCTAssertEqual(reset.received, 0); XCTAssertTrue(reset.rebased)
    let source = tracker.update(
      [.init(name: "en0", received: 1000, sent: 1000, bits: 32)], date: date.addingTimeInterval(2))[
        "en0"]!
    XCTAssertEqual(source.sent, 0); XCTAssertTrue(source.rebased)
    XCTAssertTrue(tracker.update([], date: date).isEmpty)
    let reappeared = tracker.update([.init(name: "en0", received: 100, sent: 100)], date: date)[
      "en0"]!
    XCTAssertEqual(reappeared.received, 0); XCTAssertFalse(reappeared.rebased)
    tracker.reset()
    XCTAssertEqual(
      tracker.update([.init(name: "en0", received: 1000, sent: 1000)], date: date)["en0"]?.received,
      0)
  }
  func testMalformedSessionSnapshotsCannotRetainPreviousReadings() {
    var tracker = NetworkSessionTracker()
    XCTAssertTrue(
      tracker.update(
        [.init(name: "en0", received: 0, sent: 0), .init(name: "en0", received: 1, sent: 1)],
        date: .distantPast
      ).isEmpty)
    XCTAssertTrue(
      tracker.update([.init(name: "en0", received: 0, sent: 0, bits: 16)], date: .distantPast)
        .isEmpty)
  }
  func testHistoryScopeChangePreservesOtherSeriesAndClearsPendingAggregates() {
    var history = HistoryStore()
    history.append(
      .init(
        date: Date(timeIntervalSince1970: 0),
        values: ["cpu": 30, "temperature": 40, "download": 999]))
    history.append(
      .init(date: Date(timeIntervalSince1970: 60), values: ["cpu": 50, "download": 888]))
    history.removeMetrics(["download", "upload"])
    XCTAssertEqual(history.recent.values[0].values["cpu"], 30)
    XCTAssertNil(history.recent.values[0].values["download"])
    XCTAssertEqual(history.minutes.values[0].values["temperature"], 40)
    history.append(.init(date: Date(timeIntervalSince1970: 61), values: ["download": 2]))
    history.append(.init(date: Date(timeIntervalSince1970: 120), values: [:]))
    XCTAssertEqual(history.minutes.values.last?.values["download"], 2)
  }
}
