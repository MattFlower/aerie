import AerieCore
import XCTest
@testable import AerieApp

final class NetworkAggregateTests: XCTestCase {
  private func interface(_ name: String, download: Double?, upload: Double?, active: Bool = true)
    -> InterfaceData
  {
    InterfaceData(
      name: name, active: active, addresses: "synthetic", received: 100,
      sent: 200, download: download, upload: upload, errors: 0)
  }
  func testInterfaceSelectionPreservesFullInventoryAndChangesHistoryRuleTotals() {
    var snapshot = Snapshot(); snapshot.networkAvailable = true
    snapshot.interfaces = [
      InterfaceData(
        name: "en0", active: true, addresses: "synthetic", received: 430_000_000_000,
        sent: 490_000_000_000, download: 10, upload: 20, errors: 0),
      InterfaceData(
        name: "utun1", active: true, addresses: "synthetic", received: 100, sent: 100, download: 10,
        upload: 20, errors: 0),
    ]
    XCTAssertEqual(snapshot.download, 20); XCTAssertEqual(snapshot.upload, 40)
    snapshot.networkSelection = NetworkSelection(names: ["en0"])
    XCTAssertEqual(snapshot.interfaces.count, 2);
    XCTAssertEqual(snapshot.interfaces[0].received, 430_000_000_000)
    XCTAssertEqual(snapshot.download, 10); XCTAssertEqual(snapshot.metrics["upload"], 20)
    snapshot.networkSelection = NetworkSelection(names: ["missing"])
    XCTAssertNil(snapshot.download); XCTAssertNil(snapshot.metrics["upload"])
  }
  func testIncompleteSelectedRatesStayUnavailableWhileOtherDirectionsAndInterfacesRemainVisible() {
    var snapshot = Snapshot(); snapshot.networkAvailable = true
    snapshot.interfaces = [
      interface("en0", download: 10, upload: 20), interface("utun1", download: nil, upload: 0),
    ]
    XCTAssertNil(snapshot.download); XCTAssertEqual(snapshot.upload, 20)
    XCTAssertEqual(snapshot.interfaces.count, 2);
    XCTAssertEqual(snapshot.interfaces[0].download, 10)
    snapshot.networkSelection = NetworkSelection(names: ["en0"])
    XCTAssertEqual(snapshot.download, 10); XCTAssertEqual(snapshot.upload, 20)
    snapshot.networkSelection = NetworkSelection()
    snapshot.interfaces[1].active = false
    XCTAssertEqual(snapshot.download, 10)
    snapshot.interfaces[0].download = 0; snapshot.interfaces[0].upload = 0
    XCTAssertEqual(snapshot.download, 0); XCTAssertEqual(snapshot.upload, 0)
    snapshot.networkAvailable = false
    XCTAssertNil(snapshot.download); XCTAssertNil(snapshot.upload)
    XCTAssertNil(snapshot.metrics["download"]); XCTAssertNil(snapshot.metrics["upload"])
  }
  func testInvalidOrOverflowedRateCannotBecomeACompleteAggregate() {
    for value in [Double.nan, .infinity, -.infinity, -1] {
      var snapshot = Snapshot(); snapshot.networkAvailable = true
      snapshot.interfaces = [
        interface("en0", download: 1, upload: 2),
        interface("utun1", download: value, upload: value),
      ]
      XCTAssertNil(snapshot.download); XCTAssertNil(snapshot.upload)
    }
    var snapshot = Snapshot(); snapshot.networkAvailable = true
    snapshot.interfaces = [
      interface("en0", download: .greatestFiniteMagnitude, upload: 0),
      interface("utun1", download: .greatestFiniteMagnitude, upload: 0),
    ]
    XCTAssertNil(snapshot.download); XCTAssertEqual(snapshot.upload, 0)
  }
  func
    testMissingAggregateCannotTriggerLowBandwidthRuleOrPolluteHistoryAndRecoveryStartsFreshSustain()
  {
    var snapshot = Snapshot(); snapshot.networkAvailable = true
    snapshot.interfaces = [
      interface("en0", download: 40, upload: 0), interface("utun1", download: 20, upload: 0),
    ]
    var engine = RuleEngine(), history = HistoryStore()
    let rule = ThresholdRule(metric: "download", threshold: 25, comparison: .below, duration: 10)
    XCTAssertTrue(engine.evaluate(rules: [rule], values: snapshot.metrics, time: 0).isEmpty)
    history.append(HistoryPoint(date: Date(timeIntervalSince1970: 0), values: snapshot.metrics))
    snapshot.interfaces[0].download = 10; snapshot.interfaces[1].download = nil
    for time in [5.0, 15.0] {
      XCTAssertTrue(engine.evaluate(rules: [rule], values: snapshot.metrics, time: time).isEmpty)
      history.append(
        HistoryPoint(date: Date(timeIntervalSince1970: time), values: snapshot.metrics))
    }
    snapshot.interfaces[1].download = 10
    XCTAssertTrue(engine.evaluate(rules: [rule], values: snapshot.metrics, time: 20).isEmpty)
    history.append(HistoryPoint(date: Date(timeIntervalSince1970: 20), values: snapshot.metrics))
    XCTAssertEqual(engine.evaluate(rules: [rule], values: snapshot.metrics, time: 30), [rule])
    history.append(HistoryPoint(date: Date(timeIntervalSince1970: 61), values: [:]))
    XCTAssertNil(history.recent.values[1].values["download"])
    XCTAssertNil(history.recent.values[2].values["download"])
    XCTAssertEqual(history.minutes.values[0].values["download"], 40)
    XCTAssertEqual(history.minutes.values[0].sampleCounts?["download"], 2)
  }
}
