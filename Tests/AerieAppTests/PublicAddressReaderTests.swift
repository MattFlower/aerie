import AerieCore
import Foundation
import XCTest
@testable import AerieApp

@MainActor final class PublicAddressReaderTests: XCTestCase {
  private func reading() throws -> PublicAddressReading {
    try PublicAddressReading.parse(
      Data("{\"ip\":\"203.0.113.7\"}".utf8), date: Date(timeIntervalSince1970: 1_700_000_000))
  }
  private func settle(_ predicate: () -> Bool) async {
    for _ in 0..<100 where !predicate() { await Task.yield() }
    XCTAssertTrue(predicate())
  }
  func testOffIsLazyCadenceFailuresAndRouteChangeNeverRetainLiveOldAddress() async throws {
    var calls = 0, fail = false
    let sample = try reading()
    let reader = PublicAddressReader {
      calls += 1; if fail { throw WeatherError.http(503) }; return sample
    }
    reader.tick(time: 0, route: "1"); XCTAssertEqual(calls, 0)
    reader.configure(enabled: true, suspended: false)
    reader.tick(time: 0, route: "1"); await settle { reader.reading != nil }
    XCTAssertEqual(calls, 1)
    reader.tick(time: 299, route: "1"); XCTAssertEqual(calls, 1)
    reader.tick(time: 299, route: "2"); XCTAssertNil(reader.reading)
    XCTAssertEqual(calls, 1)
    fail = true; reader.tick(time: 300, route: "2")
    await settle { reader.status.contains("unavailable") }
    XCTAssertNil(reader.reading); XCTAssertEqual(calls, 2)
    reader.tick(time: 599, route: "2"); XCTAssertEqual(calls, 2)
    fail = false; reader.tick(time: 600, route: "2"); await settle { reader.reading != nil }
    reader.tick(time: 601, route: nil); XCTAssertNil(reader.reading)
    reader.stop(); XCTAssertNil(reader.reading)
  }
  func testPauseDisableAndCancellationRejectLateIgnoringSourceCompletion() async throws {
    var completions: [CheckedContinuation<PublicAddressReading, Error>] = []
    let sample = try reading()
    let reader = PublicAddressReader {
      try await withCheckedThrowingContinuation { completions.append($0) }
    }
    reader.configure(enabled: true, suspended: false); reader.tick(time: 0, route: "1")
    await settle { completions.count == 1 }
    reader.configure(enabled: true, suspended: true)
    completions.removeFirst().resume(returning: sample)
    await Task.yield(); XCTAssertNil(reader.reading)
    reader.tick(time: 400, route: "1"); XCTAssertTrue(completions.isEmpty)
    reader.configure(enabled: true, suspended: false); reader.tick(time: 400, route: "1")
    await settle { completions.count == 1 }
    reader.configure(enabled: false, suspended: false)
    completions.removeFirst().resume(returning: sample)
    await Task.yield(); XCTAssertNil(reader.reading); XCTAssertTrue(reader.status.contains("off"))
  }
  func testMissingPathNeverRequestsAndTimeRollbackReestablishesCadence() async throws {
    var calls = 0; let sample = try reading()
    let reader = PublicAddressReader {
      calls += 1; return sample
    }
    reader.configure(enabled: true, suspended: false); reader.tick(time: 500, route: nil)
    XCTAssertEqual(calls, 0)
    reader.tick(time: 501, route: "1"); await settle { calls == 1 }
    reader.tick(time: 1, route: "1"); await settle { calls == 2 }
    reader.stop(); reader.tick(time: 900, route: "1"); XCTAssertEqual(calls, 2)
  }
}
