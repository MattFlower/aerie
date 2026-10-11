import XCTest
@testable import AerieApp

final class SamplingProfilerTests: XCTestCase {
  func testSequentialPhasesSeparateThreadCPUAndBlockedWallTimeAndResetWindows() throws {
    var stamps = [
      SamplingProfiler.Stamp(wall: 100, cpu: 10), .init(wall: 200, cpu: 20),
      .init(wall: 1200, cpu: 30), .init(wall: 1300, cpu: 50),
    ]
    var reports: [SamplingProfiler.Report] = []
    let profiler = SamplingProfiler(
      scope: "fixture", window: 1, clock: { stamps.removeFirst() }, emit: { reports.append($0) })
    profiler.begin(.clockPrepare); profiler.mark(.clockNative); profiler.finish()
    XCTAssertEqual(reports.count, 1)
    XCTAssertEqual(reports[0].phases["clockPrepare"]?.observedWallNanoseconds, 100)
    XCTAssertEqual(reports[0].phases["clockPrepare"]?.observedCPUNanoseconds, 10)
    XCTAssertEqual(reports[0].phases["clockNative"]?.observedWallNanoseconds, 1000)
    XCTAssertEqual(reports[0].phases["clockNative"]?.observedCPUNanoseconds, 10)
    stamps.append(.init(wall: 1500, cpu: 60))
    profiler.begin(.cpu); profiler.finish()
    XCTAssertEqual(reports.count, 2); XCTAssertNil(reports[1].phases["clockNative"])
    XCTAssertEqual(reports[1].phases["cpu"]?.observedCPUNanoseconds, 10)
    let data = try JSONEncoder().encode(reports[0])
    let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(Set(decoded.keys), ["kind", "schema", "scope", "ticks", "phases"])
  }
  func testUnavailableReversingAndOverflowingCountersRetainExplicitCoverage() {
    var stamps = [
      SamplingProfiler.Stamp(wall: 100, cpu: nil), .init(wall: 200, cpu: 20),
      .init(wall: 150, cpu: 10), .init(wall: 0, cpu: 0),
      .init(wall: .max, cpu: .max), .init(wall: 0, cpu: 0),
      .init(wall: 1, cpu: 1),
    ]
    var reports: [SamplingProfiler.Report] = []
    let profiler = SamplingProfiler(
      scope: "fixture", window: 3, clock: { stamps.removeFirst() }, emit: { reports.append($0) })
    profiler.begin(.sensors); profiler.mark(.memory); profiler.finish()
    profiler.begin(.cpu); profiler.finish()
    profiler.begin(.cpu); profiler.finish()
    XCTAssertEqual(reports.count, 1)
    XCTAssertEqual(reports[0].phases["sensors"]?.cpuSamples, 0)
    XCTAssertEqual(reports[0].phases["memory"]?.cpuSamples, 0)
    XCTAssertEqual(reports[0].phases["memory"]?.invalidWallSamples, 1)
    XCTAssertEqual(reports[0].phases["cpu"]?.calls, 2)
    XCTAssertEqual(reports[0].phases["cpu"]?.cpuSamples, 1)
    XCTAssertEqual(reports[0].phases["cpu"]?.invalidWallSamples, 1)
  }
  func testInactiveProfilerNeverReadsAClockOrEmitsAReport() {
    let profiler = SamplingProfiler(
      scope: "fixture",
      clock: {
        XCTFail("Unexpected timing read"); return .init(wall: 0, cpu: nil)
      }, emit: { _ in XCTFail("Unexpected report") })
    profiler.mark(.clockNative); profiler.finish()
  }
}
