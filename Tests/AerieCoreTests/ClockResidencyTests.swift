import Foundation
import XCTest
@testable import AerieCore

final class ClockResidencyTests: XCTestCase {
  private func counter(_ values: [(String, UInt64)], identity: String = "synthetic") -> ClockCounter
  {
    ClockCounter(
      kind: .cpuComplex, identity: identity, name: "Fixture complex", unit: "ticks",
      states: values.map { (name: $0.0, ticks: $0.1) })
  }
  func testFirstReadingNeedsBaselineAndNamedFrequenciesWeightOnlyActiveStates() {
    var tracker = ClockResidencyTracker()
    let first = counter([("IDLE", 100), ("600 MHz", 100), ("1.2 GHz", 100)])
    XCTAssertNil(tracker.update([first], time: 1)[0].activeFraction)
    let row = tracker.update(
      [counter([("IDLE", 120), ("600 MHz", 120), ("1.2 GHz", 160)])], time: 2)[0]
    XCTAssertEqual(row.activeFraction!, 0.8, accuracy: 1e-9)
    XCTAssertEqual(row.activeGHz!, 1.05, accuracy: 1e-9)
    XCTAssertEqual(row.states.reduce(0) { $0 + $1.fraction }, 1, accuracy: 1e-9)
  }
  func testNamedPerformanceIndicesAreNotInventedFrequenciesAndUnknownOccupiedStatesAreUnavailable()
  {
    var tracker = ClockResidencyTracker()
    _ = tracker.update([counter([("DOWN", 0), ("V0P14", 0), ("UNKNOWN", 0)])], time: 1)
    let indexed = tracker.update(
      [counter([("DOWN", 20), ("V0P14", 80), ("UNKNOWN", 0)])], time: 2)[0]
    XCTAssertEqual(indexed.activeFraction!, 0.8, accuracy: 1e-9); XCTAssertNil(indexed.activeGHz)
    let unknown = tracker.update(
      [counter([("DOWN", 40), ("V0P14", 160), ("UNKNOWN", 1)])], time: 3)[0]
    XCTAssertNil(unknown.activeFraction); XCTAssertNil(unknown.activeGHz)
    XCTAssertEqual(unknown.states.count, 3)
  }
  func testIdleZeroIsValidButStoppedCounterAndMissingChannelAreUnavailable() {
    var tracker = ClockResidencyTracker()
    _ = tracker.update([counter([("OFF", 0), ("P1", 0)])], time: 1)
    let idle = tracker.update([counter([("OFF", 100), ("P1", 0)])], time: 2)[0]
    XCTAssertEqual(idle.activeFraction, 0); XCTAssertNil(idle.activeGHz)
    XCTAssertNil(tracker.update([counter([("OFF", 100), ("P1", 0)])], time: 3)[0].activeFraction)
    XCTAssertTrue(tracker.update([], time: 4).isEmpty)
    XCTAssertNil(tracker.update([counter([("OFF", 200), ("P1", 100)])], time: 5)[0].activeFraction)
  }
  func testChannelsWithoutAnInactiveBucketDoNotClaimCompleteActivityCoverage() {
    var tracker = ClockResidencyTracker()
    _ = tracker.update([counter([("600 MHz", 0), ("1.2 GHz", 0)])], time: 1)
    let row = tracker.update([counter([("600 MHz", 50), ("1.2 GHz", 50)])], time: 2)[0]
    XCTAssertNil(row.activeFraction)
    XCTAssertEqual(row.activeGHz!, 0.9, accuracy: 1e-9)
    XCTAssertEqual(row.states.reduce(0) { $0 + $1.fraction }, 1, accuracy: 1e-9)
  }
  func testCounterResetLongGapClockReversalUnitOrStateTopologyChangeRequireNewBaseline() {
    for change in 0..<5 {
      var tracker = ClockResidencyTracker()
      _ = tracker.update([counter([("IDLE", 100), ("P1", 100)])], time: 10)
      var next = counter([("IDLE", 110), ("P1", 120)])
      let now: Double
      switch change {
      case 0: next.states[0].ticks = 1; now = 11
      case 1: now = 100
      case 2: now = 9
      case 3: next.unit = "new unit"; now = 11
      default: next.states[1].name = "P2"; now = 11
      }
      XCTAssertNil(tracker.update([next], time: now)[0].activeFraction)
    }
  }
  func testOverflowDuplicateIdentitiesMalformedOrUnboundedInputNeverProduceAValue() {
    var tracker = ClockResidencyTracker()
    _ = tracker.update([counter([("IDLE", 0), ("P1", 0)])], time: 1)
    XCTAssertNil(
      tracker.update([counter([("IDLE", .max), ("P1", .max)])], time: 2)[0].activeFraction)
    let normal = counter([("IDLE", 0), ("P1", 0)])
    XCTAssertTrue(tracker.update([normal, normal], time: 3).isEmpty)
    XCTAssertTrue(tracker.update([counter([("", 0)])], time: 4).isEmpty)
    XCTAssertTrue(tracker.update([normal], time: .nan).isEmpty)
    XCTAssertTrue(
      tracker.update((0..<129).map { counter([("OFF", 0)], identity: "\($0)") }, time: 5).isEmpty)
    tracker.reset(); XCTAssertNil(tracker.update([normal], time: 6)[0].activeFraction)
  }
}
