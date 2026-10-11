import AerieCore
import XCTest
@testable import AerieApp

private final class SyntheticClockSource: ClockStateSource {
  var closed = false, ticks: UInt64 = 0
  var statuses: [Int32] = [0, 0, 0]
  func read() -> ClockSourceReading {
    ticks += 100
    return ClockSourceReading(
      counters: [
        ClockCounter(
          kind: .gpu, identity: "fixture", name: "Fixture",
          unit: "ticks", states: [("OFF", ticks), ("P1", ticks)])
      ], statuses: statuses)
  }
  func close() { closed = true }
}
final class ClockStateReaderTests: XCTestCase {
  func testUnavailableLibraryRetriesAtMostOncePerMinuteAndResumeCanRetryImmediately() {
    var attempts = 0
    let reader = ClockStateReader(factory: {
      attempts += 1; return nil
    })
    XCTAssertTrue(reader.sample(time: 100).rows.isEmpty)
    XCTAssertTrue(reader.sample(time: 159).status.contains("unavailable"));
    XCTAssertEqual(attempts, 1)
    _ = reader.sample(time: 160); XCTAssertEqual(attempts, 2)
    reader.close(); _ = reader.sample(time: 161); XCTAssertEqual(attempts, 3)
  }
  func testCloseReleasesSourceAndReopenCannotUseAPreviousCounterBaseline() {
    weak var weakSource: SyntheticClockSource?
    var source: SyntheticClockSource?
    let reader = ClockStateReader(factory: {
      let value = SyntheticClockSource(); source = value; weakSource = value; return value
    })
    XCTAssertNil(reader.sample(time: 100).rows[0].activeFraction)
    XCTAssertEqual(reader.sample(time: 101).rows[0].activeFraction, 0.5)
    reader.close(); XCTAssertTrue(source!.closed); source = nil; XCTAssertNil(weakSource)
    XCTAssertNil(reader.sample(time: 102).rows[0].activeFraction)
    reader.close(); source = nil; XCTAssertNil(weakSource)
  }
  func testFailurePartialInventoryAndMalformedStatusRemainExplicitAndResetOnReconnect() {
    var sources: [SyntheticClockSource] = []
    let reader = ClockStateReader(factory: {
      let value = SyntheticClockSource(); sources.append(value); return value
    })
    _ = reader.sample(time: 100); sources[0].statuses = [3, 5, 0]
    let reading = reader.sample(time: 101)
    XCTAssertTrue(reading.status.contains("subscription unavailable"))
    XCTAssertTrue(reading.status.contains("partial inventory"))
    XCTAssertEqual(reading.rows[0].activeFraction, 0.5)
    _ = reader.sample(time: 159); XCTAssertEqual(sources.count, 1)
    XCTAssertNil(reader.sample(time: 160).rows[0].activeFraction); XCTAssertTrue(sources[0].closed)
    sources[1].statuses = []; XCTAssertTrue(reader.sample(time: 161).rows.isEmpty)
    XCTAssertTrue(reader.sample(time: 162).status.contains("system interface unavailable"))
  }
}
