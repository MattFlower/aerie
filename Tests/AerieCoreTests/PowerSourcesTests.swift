import XCTest
@testable import AerieCore

final class PowerSourcesTests: XCTestCase {
  private func reading(
    kind: PowerSourceKind = .internalBattery, present: Bool? = true,
    current: Double? = 0, maximum: Double? = 100, minutes: Int? = 0,
    voltage: Double? = 12, currentAmps: Double? = -2
  ) -> PowerSourceReading {
    PowerSourceReading(
      name: "Fixture", kind: kind, transport: nil, present: present, input: .battery,
      charging: false, current: current, maximum: maximum, minutes: minutes,
      voltage: voltage, amperage: currentAmps, temperature: 20)
  }
  func testCapacityAndElectricalValuesPreserveZeroAndRejectInvalidOrAbsentReadings() {
    XCTAssertEqual(reading().percent, 0); XCTAssertEqual(reading().minutes, 0)
    XCTAssertEqual(reading().watts, -24)
    for (current, maximum) in [
      (Double.nan, 100), (.infinity, 100), (-1, 100), (101, 100), (0, 0), (1, .nan),
    ] {
      XCTAssertNil(reading(current: current, maximum: maximum).percent)
    }
    for present in [nil, false] as [Bool?] {
      let absent = reading(present: present)
      XCTAssertNil(absent.percent); XCTAssertNil(absent.minutes); XCTAssertNil(absent.watts)
      XCTAssertNil(absent.temperature)
    }
    XCTAssertNil(reading(minutes: -1).minutes); XCTAssertNil(reading(minutes: .max).minutes)
    XCTAssertNil(reading(voltage: -1).watts)
    XCTAssertNil(reading(voltage: .greatestFiniteMagnitude, currentAmps: 2).watts)
  }
  func testMixedSourceOrderingNeverLetsUPSOverwriteAnInternalBattery() {
    let battery = reading(current: 30), ups = reading(kind: .ups, current: 90)
    for sources in [[battery, ups], [ups, battery]] {
      let inventory = PowerSourceInventory(sources: sources, available: true, reportedCount: 2)
      XCTAssertEqual(inventory.primaryBattery?.percent, 0.3)
    }
    XCTAssertNil(
      PowerSourceInventory(sources: [ups], available: true, reportedCount: 1).primaryBattery)
    XCTAssertNil(
      PowerSourceInventory(sources: [battery, battery], available: true, reportedCount: 2)
        .primaryBattery)
  }
  func testTimeContextAndFormattingKeepMissingStatesAndZeroEstimatesDistinct() {
    for input in [PowerInputState.ac, .offline, .unknown] {
      let reading = PowerSourceReading(
        name: nil, kind: .ups, transport: nil, present: true,
        input: input, charging: false, current: 50, maximum: 100, minutes: 0,
        voltage: nil, amperage: nil, temperature: nil)
      XCTAssertNil(reading.minutes)
    }
    XCTAssertEqual(Format.powerTime(0, charging: false, input: .ac), "Not discharging")
    XCTAssertEqual(Format.powerTime(nil, charging: false, input: .ac), "Not discharging")
    XCTAssertEqual(Format.powerTime(0, charging: false, input: .battery), "0h 0m")
    XCTAssertEqual(Format.powerTime(0, charging: true, input: .ac), "0h 0m")
    XCTAssertEqual(Format.powerTime(30, charging: false, input: .battery), "0h 30m")
    XCTAssertEqual(Format.powerTime(30, charging: true, input: .ac), "0h 30m")
    for (input, charging) in [(PowerInputState.unknown, false), (.offline, false), (.battery, nil)]
      as [(PowerInputState, Bool?)]
    {
      XCTAssertEqual(
        Format.powerTime(0, charging: charging, input: input), "Unavailable or calculating")
    }
    XCTAssertEqual(Format.powerTime(-1, charging: true, input: .ac), "Unavailable or calculating")
    XCTAssertEqual(Format.powerTime(.max, charging: true, input: .ac), "Unavailable or calculating")
  }
  func testDurationFormattingRejectsValuesThatCannotConvertSafelyToIntegerSeconds() {
    for value in [Double.infinity, .nan, .greatestFiniteMagnitude, Double(Int.max), -1] {
      XCTAssertEqual(Format.duration(value), "Unavailable")
    }
    XCTAssertEqual(Format.duration(0), "0h 0m")
    XCTAssertNotEqual(Format.duration(Double(Int.max).nextDown), "Unavailable")
  }
  func testIncompleteUnknownAndTruncatedInventoryCannotInventUniqueBatterySummary() {
    let battery = reading()
    for inventory in [
      PowerSourceInventory(sources: [battery]),
      PowerSourceInventory(
        sources: [battery], available: true, reportedCount: 2, unreadableCount: 1),
      PowerSourceInventory(
        sources: [battery, reading(kind: .unknown)], available: true, reportedCount: 2),
      PowerSourceInventory(
        sources: [battery, reading(kind: .ups, present: nil)], available: true, reportedCount: 2),
      PowerSourceInventory(
        sources: Array(repeating: battery, count: 65), available: true, reportedCount: 65),
    ] { XCTAssertNil(inventory.primaryBattery) }
    let bounded = PowerSourceInventory(
      sources: Array(repeating: battery, count: 65), available: true, reportedCount: 65)
    XCTAssertEqual(bounded.sources.count, 64); XCTAssertFalse(bounded.complete)
    let absentSlot = PowerSourceInventory(
      sources: [battery, reading(present: false)], available: true, reportedCount: 2)
    XCTAssertEqual(absentSlot.primaryBattery, battery)
  }
  func testUntrustedLabelsHaveScalarAndControlBounds() {
    let value = PowerSourceReading(
      name: "\n" + String(repeating: "🚀", count: 1000), kind: .ups,
      transport: "\0 USB\n", present: true, input: .ac, charging: nil,
      current: 50, maximum: 100, minutes: 30, voltage: nil, amperage: nil, temperature: .infinity)
    XCTAssertLessThanOrEqual(value.name.utf8.count, 512)
    XCTAssertFalse(value.name.contains("\n")); XCTAssertEqual(value.transport, "USB")
    XCTAssertNil(value.minutes); XCTAssertNil(value.temperature)
  }
}
