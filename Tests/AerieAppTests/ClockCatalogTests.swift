import AerieNative
import XCTest

final class ClockCatalogTests: XCTestCase {
  func testFullCatalogKeepsKindsWhenChannelOrderChanges() {
    let catalog = [
      AerieClockIdentity(kind: 2, driver_id: 20, channel_id: 1),
      AerieClockIdentity(kind: 0, driver_id: 10, channel_id: 1),
      AerieClockIdentity(kind: 1, driver_id: 10, channel_id: 2),
    ]
    XCTAssertEqual(aerie_clock_catalog_valid(catalog, 3), 1)
    XCTAssertEqual(aerie_clock_catalog_kind(catalog, 3, 10, 2), 1)
    XCTAssertEqual(aerie_clock_catalog_kind(catalog, 3, 20, 1), 2)
    XCTAssertEqual(aerie_clock_catalog_kind(catalog, 3, 10, 1), 0)
    XCTAssertEqual(aerie_clock_catalog_kind(catalog, 3, 99, 1), -1)
    XCTAssertEqual(aerie_clock_catalog_kind(catalog, 3, 10, 99), -1)
  }
  func testAmbiguousIdentityCannotBeAssignedAGroup() {
    for secondKind in [Int32(0), 1, 2] {
      let catalog = [
        AerieClockIdentity(kind: 0, driver_id: 1, channel_id: 2),
        AerieClockIdentity(kind: secondKind, driver_id: 1, channel_id: 2),
      ]
      XCTAssertEqual(aerie_clock_catalog_valid(catalog, 2), 0)
      XCTAssertEqual(aerie_clock_catalog_kind(catalog, 2, 1, 2), -1)
    }
  }
  func testInvalidKindsAndCatalogBoundsRemainUnavailable() {
    let invalid = [AerieClockIdentity(kind: 3, driver_id: 1, channel_id: 2)]
    XCTAssertEqual(aerie_clock_catalog_valid(invalid, 1), 0)
    XCTAssertEqual(aerie_clock_catalog_kind(invalid, 1, 1, 2), -1)
    for count in [Int32(-1), 0, 129] {
      XCTAssertEqual(aerie_clock_catalog_valid(nil, count), 0)
      XCTAssertEqual(aerie_clock_catalog_kind(nil, count, 1, 2), -1)
    }
    let full = (0..<128).map {
      AerieClockIdentity(kind: Int32($0 % 3), driver_id: 1, channel_id: UInt64($0))
    }
    XCTAssertEqual(aerie_clock_catalog_valid(full, 128), 1)
    XCTAssertEqual(aerie_clock_catalog_kind(full, 128, 1, 127), 1)
    XCTAssertEqual(aerie_performance_subscription_count(nil), 0)
  }
}
