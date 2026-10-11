import XCTest
@testable import AerieCore

final class ProcessNetworkTests: XCTestCase {
  private func data(_ string: String) -> Data { Data(string.utf8) }
  func testFragmentedCSVFramesKeepLargeCountersAndQuotedNames() throws {
    var parser = ProcessNetworkCSV()
    XCTAssertTrue(
      try parser.consume(data(",bytes_in,bytes_out,\n\"Synthetic, app.42\",430000000000,"), time: 1)
        .isEmpty)
    let frames = try parser.consume(data("490000000000,\n,bytes_in,bytes_out,\n"), time: 2)
    XCTAssertEqual(frames.count, 1); XCTAssertEqual(frames[0].time, 1)
    XCTAssertEqual(frames[0].counters[0].pid, 42)
    XCTAssertEqual(frames[0].counters[0].name, "Synthetic, app")
    XCTAssertEqual(frames[0].counters[0].received, 430_000_000_000)
    XCTAssertEqual(frames[0].counters[0].sent, 490_000_000_000)
  }
  func testHeaderColumnOrderAndEmptyFramesAreExplicit() throws {
    var parser = ProcessNetworkCSV()
    let frames = try parser.consume(
      data(
        ",bytes_out,bytes_in,\nSynthetic.4,20,10,\n,bytes_in,bytes_out,\n,bytes_in,bytes_out,\n"),
      time: 1)
    XCTAssertEqual(frames.count, 2); XCTAssertEqual(frames[0].counters[0].received, 10)
    XCTAssertEqual(frames[0].counters[0].sent, 20); XCTAssertTrue(frames[1].counters.isEmpty)
  }
  func testMalformedHeadersCountersIdentityDuplicatesAndBoundsFailClosed() {
    for text in [
      ",unknown,bytes_out,\n", "Synthetic.4,1,2,\n", ",bytes_in,bytes_out,\nSynthetic,1,2,\n",
      ",bytes_in,bytes_out,\nSynthetic.4,-1,2,\n",
      ",bytes_in,bytes_out,\nSynthetic.4,18446744073709551616,2,\n",
      ",bytes_in,bytes_out,\nSynthetic.4,1,2,\nOther.4,3,4,\n",
      ",bytes_in,bytes_out,\n\"unterminated.4,1,2,\n", String(repeating: "x", count: 2049),
    ] {
      var parser = ProcessNetworkCSV();
      XCTAssertThrowsError(try parser.consume(data(text), time: 1))
    }
    var parser = ProcessNetworkCSV()
    XCTAssertThrowsError(try parser.consume(Data(repeating: 0, count: 65537), time: 1))
  }
  func testUnattributedKernelRowsDoNotDiscardValidUserProcessCoverage() throws {
    var parser = ProcessNetworkCSV(); var rates = ProcessNetworkRates()
    let frames = try parser.consume(
      data(
        ",bytes_in,bytes_out,\nSyntheticKernel.0,10,20,\nSyntheticApp.42,30,40,\n,bytes_in,bytes_out,\n"
      ), time: 1)
    var queried: [Int32] = []
    let result = rates.update(frames[0]) {
      queried.append($0); return 99
    }
    XCTAssertEqual(queried, [42]); XCTAssertEqual(result.denied, 1)
    XCTAssertEqual(result.rows.count, 1); XCTAssertEqual(result.rows[0].pid, 42)
  }
  func testRatesDoNotCreditPreviousProcessOrMissingAndResetCounters() {
    var rates = ProcessNetworkRates()
    func frame(_ time: Double, _ received: UInt64, _ sent: UInt64) -> ProcessNetworkFrame {
      .init(
        time: time, counters: [.init(pid: 42, name: "Synthetic", received: received, sent: sent)])
    }
    let initial = rates.update(frame(1, 100, 100), identity: { _ in 99 })
    XCTAssertNil(initial.rows[0].download)
    let live = rates.update(frame(3, 140, 160), identity: { _ in 99 })
    XCTAssertEqual(live.rows[0].download, 20); XCTAssertEqual(live.rows[0].upload, 30)
    XCTAssertNil(rates.update(frame(4, 150, 170), identity: { _ in 100 }).rows[0].download)
    let denied = rates.update(frame(5, 150, 170), identity: { _ in nil })
    XCTAssertEqual(denied.denied, 1); XCTAssertTrue(denied.rows.isEmpty)
    XCTAssertNil(rates.update(frame(6, 160, 180), identity: { _ in 100 }).rows[0].download)
    let reset = rates.update(frame(7, 1, 200), identity: { _ in 100 })
    XCTAssertNil(reset.rows[0].download); XCTAssertNil(reset.rows[0].upload)
    XCTAssertNil(rates.update(frame(100, 3, 4), identity: { _ in 100 }).rows[0].download)
    _ = rates.update(.init(time: 101, counters: []), identity: { _ in 100 })
    XCTAssertNil(rates.update(frame(102, 5, 6), identity: { _ in 100 }).rows[0].download)
  }
}
