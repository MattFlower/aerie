import AerieCore
import XCTest
@testable import AerieApp

final class NetworkAggregateTests: XCTestCase {
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
}
