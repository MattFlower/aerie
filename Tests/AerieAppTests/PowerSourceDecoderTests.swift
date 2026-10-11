import AerieCore
import IOKit.ps
import XCTest
@testable import AerieApp

final class PowerSourceDecoderTests: XCTestCase {
  private func fixture(type: String = kIOPSInternalBatteryType, charge: Int = 30) -> [String: Any] {
    [
      kIOPSTypeKey: type, kIOPSNameKey: "Synthetic source", kIOPSIsPresentKey: true,
      kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargingKey: true,
      kIOPSCurrentCapacityKey: charge, kIOPSMaxCapacityKey: 100,
      kIOPSTimeToFullChargeKey: 15, kIOPSTimeToEmptyKey: 200,
      kIOPSVoltageKey: 12000, kIOPSCurrentKey: -2000, kIOPSTemperatureKey: 22,
    ]
  }
  func testDocumentedUnitsAndTimeSelectionPreserveSignedCurrent() {
    var details = fixture()
    var reading = PowerSourceDecoder.decode(details)
    XCTAssertEqual(reading.percent, 0.3); XCTAssertEqual(reading.minutes, 15)
    XCTAssertEqual(reading.voltage, 12); XCTAssertEqual(reading.amperage, -2)
    XCTAssertEqual(reading.watts, -24); XCTAssertEqual(reading.temperature, 22)
    details[kIOPSIsChargingKey] = false
    reading = PowerSourceDecoder.decode(details)
    XCTAssertEqual(reading.minutes, 200); XCTAssertEqual(reading.charging, false)
    details[kIOPSIsChargingKey] = nil
    XCTAssertNil(PowerSourceDecoder.decode(details).minutes)
  }
  func testBooleanNumbersSentinelsAndOverflowCannotBecomeValidCapacityOrTime() {
    for invalid: Any in [true, Double.nan, Double.infinity, -1, 0.5, UInt64.max] {
      XCTAssertNil(PowerSourceDecoder.integer(invalid))
    }
    XCTAssertNil(PowerSourceDecoder.number(true)); XCTAssertNil(PowerSourceDecoder.boolean(1))
    for key in [kIOPSCurrentCapacityKey, kIOPSMaxCapacityKey, kIOPSIsPresentKey] {
      var details = fixture(); details[key] = key == kIOPSIsPresentKey ? 1 : true
      XCTAssertNil(PowerSourceDecoder.decode(details).percent)
    }
    var details = fixture(); details[kIOPSTimeToFullChargeKey] = -1
    XCTAssertNil(PowerSourceDecoder.decode(details).minutes)
    details[kIOPSPowerSourceStateKey] = "Unspecified"; details[kIOPSTypeKey] = "Future"
    XCTAssertEqual(PowerSourceDecoder.decode(details).input, .unknown)
    XCTAssertEqual(PowerSourceDecoder.decode(details).kind, .unknown)
  }
  func testSourceOrderUPSAndUnreadableDescriptionsKeepSummaryHonest() {
    let battery = fixture(), ups = fixture(type: kIOPSUPSType, charge: 90)
    for sources in [[battery, ups], [ups, battery]] {
      let data = PowerSourceDecoder.data(
        descriptions: sources, reportedCount: 2, suppliedSource: "UPS Power")
      XCTAssertEqual(data.percent, 0.3); XCTAssertEqual(data.sourceLabel, "UPS")
      XCTAssertEqual(data.inventory.sources.count, 2); XCTAssertTrue(data.inventory.complete)
    }
    let onlyUPS = PowerSourceDecoder.data(
      descriptions: [ups], reportedCount: 1, suppliedSource: "UPS Power")
    XCTAssertFalse(onlyUPS.present); XCTAssertNil(onlyUPS.percent)
    let partial = PowerSourceDecoder.data(
      descriptions: [battery, nil], reportedCount: 2, suppliedSource: nil)
    XCTAssertTrue(partial.present); XCTAssertNil(partial.percent); XCTAssertNil(partial.charging)
    XCTAssertFalse(partial.inventory.complete); XCTAssertEqual(partial.inventory.unreadableCount, 1)
    let many = PowerSourceDecoder.data(
      descriptions: Array(repeating: battery, count: 65), reportedCount: 65, suppliedSource: nil)
    XCTAssertEqual(many.inventory.sources.count, 64); XCTAssertFalse(many.inventory.complete)
  }
  func testUnavailableChargeCannotTriggerFalseChargingTransitionOrClaimACSupply() {
    var snapshot = Snapshot(); snapshot.power.present = true
    XCTAssertNil(snapshot.changeStates[.charging]); XCTAssertEqual(snapshot.power.sourceLabel, "—")
    snapshot.power.charging = false
    XCTAssertEqual(snapshot.changeStates[.charging], "Not charging")
    snapshot.power.charging = true
    XCTAssertEqual(snapshot.changeStates[.charging], "Charging")
  }
  func testNativeSourceRowsIncludeUPSAndUnavailableInventory() {
    let inventory = PowerSourceDecoder.data(
      descriptions: [fixture(), fixture(type: kIOPSUPSType)], reportedCount: 3, suppliedSource: nil
    ).inventory
    let rows = DashboardController.powerSourceRows(inventory)
    let metrics = rows.compactMap { row -> String? in
      if case .metric(let label, let value) = row { return label + ": " + value }
      return nil
    }
    XCTAssertTrue(metrics.contains("Type: UPS"));
    XCTAssertTrue(metrics.contains("Type: Internal battery"))
    XCTAssertTrue(
      rows.contains {
        if case .note(let text) = $0 { return text.contains("Partial inventory") }; return false
      })
    XCTAssertTrue(
      DashboardController.powerSourceRows(PowerSourceInventory()).contains {
        if case .note(let text) = $0 { return text.contains("unavailable") }; return false
      })
  }
}
