import AerieCore
import Foundation
import XCTest
@testable import AerieApp

private final class SyntheticPermission: CalendarPermissionRequest {
  var completion: ((Bool) -> Void)?
  func request(_ completion: @escaping (Bool) -> Void) { self.completion = completion }
  func finish(_ granted: Bool) { let callback = completion; completion = nil; callback?(granted) }
}
private final class SyntheticAccessState {
  private let lock = NSLock()
  private var enabled = true
  var allowed: Bool { lock.lock(); defer { lock.unlock() }; return enabled }
  func revoke() { lock.lock(); enabled = false; lock.unlock() }
}
private final class SyntheticEventSource: CalendarEventSource {
  func configure(calendars: [String]?) { XCTAssertNil(calendars) }
  var count = 10_000, scanned = 0, closed = false
  var started: (() -> Void)?
  var beforeVisit: ((Int) -> Void)?
  var released: (() -> Void)?
  func enumerate(
    range: DateInterval, cancelled: @escaping () -> Bool,
    visit: @escaping (CalendarEventRecord) -> Bool
  ) {
    XCTAssertFalse(Thread.isMainThread)
    started?()
    for index in 0..<count {
      beforeVisit?(index)
      if cancelled() { return }
      scanned += 1
      let start = range.start.addingTimeInterval(Double(count - index))
      let event = CalendarEventRecord(
        start: start, end: start.addingTimeInterval(1),
        title: String(repeating: "T", count: 1000), calendar: String(repeating: "C", count: 1000),
        location: String(repeating: "L", count: 1000), notes: String(repeating: "N", count: 5000))
      if !visit(event) { return }
    }
  }
  func close() { XCTAssertFalse(Thread.isMainThread); closed = true; released?() }
}
final class CalendarEventReaderTests: XCTestCase {
  private let range = DateInterval(start: Date(timeIntervalSince1970: 100), duration: 86_400)
  func testDenseUnorderedEnumerationBoundsScanResultsAndDetailsOffMainThread() async {
    let source = SyntheticEventSource(), done = expectation(description: "Bounded result")
    let reader = CalendarEventReader(access: CalendarAccess(status: { true }), factory: { source })
    reader.load(ranges: [range]) { result in
      XCTAssertTrue(Thread.isMainThread); XCTAssertFalse(result.denied)
      let section = result.ranges[0]
      XCTAssertEqual(section.scanned, 2000); XCTAssertTrue(section.truncated)
      XCTAssertEqual(section.events.count, 20)
      XCTAssertEqual(section.events.first?.start, self.range.start.addingTimeInterval(8001))
      XCTAssertEqual(section.events.map(\.start), section.events.map(\.start).sorted())
      XCTAssertEqual(section.events[0].title.count, 256)
      XCTAssertEqual(section.events[0].calendar.count, 128)
      XCTAssertEqual(section.events[0].location.count, 512)
      XCTAssertEqual(section.events[0].notes.count, 2048)
      XCTAssertTrue(source.closed); done.fulfill()
    }
    await fulfillment(of: [done], timeout: 3)
  }
  func testCloseAndRapidReopenDiscardLateQueryAndReleaseItsSource() async {
    let first = SyntheticEventSource(), second = SyntheticEventSource()
    second.count = 1
    let started = expectation(description: "Old query started"),
      closed = expectation(description: "Old source closed")
    let delivered = expectation(description: "New query result"),
      block = DispatchSemaphore(value: 0)
    first.started = {
      started.fulfill(); block.wait()
    }; first.released = { closed.fulfill() }
    var factories = 0
    let reader = CalendarEventReader(
      access: CalendarAccess(status: { true }),
      factory: {
        factories += 1; return factories == 1 ? first : second
      })
    reader.load(ranges: [range]) { _ in XCTFail("Closed query delivered late events") }
    await fulfillment(of: [started], timeout: 1)
    reader.cancel()
    reader.load(ranges: [range]) { result in
      XCTAssertEqual(result.ranges[0].scanned, 1); XCTAssertTrue(second.closed); delivered.fulfill()
    }
    block.signal()
    await fulfillment(of: [closed, delivered], timeout: 2)
    XCTAssertEqual(first.scanned, 0)
  }
  func testDeniedAndRevokedAccessPublishNoDetailsWithoutRequestingPermission() async {
    let denied = expectation(description: "Denied"), revoked = expectation(description: "Revoked")
    let reader = CalendarEventReader(
      access: CalendarAccess(status: { false }),
      factory: {
        XCTFail("Denied access created an event source"); return SyntheticEventSource()
      })
    reader.load(ranges: [range]) { result in
      XCTAssertTrue(result.denied); XCTAssertTrue(result.ranges.isEmpty); denied.fulfill()
    }
    await fulfillment(of: [denied], timeout: 1)
    let state = SyntheticAccessState(), source = SyntheticEventSource()
    source.beforeVisit = { if $0 == 10 { state.revoke() } }
    let other = CalendarEventReader(
      access: CalendarAccess(status: { state.allowed }), factory: { source })
    other.load(ranges: [range]) { result in
      XCTAssertTrue(result.denied); XCTAssertTrue(result.ranges.isEmpty);
      XCTAssertTrue(source.closed); revoked.fulfill()
    }
    await fulfillment(of: [revoked], timeout: 2)
    XCTAssertEqual(source.scanned, 10)
  }
  func testPermissionAttemptReleasesStoreOnDenialGrantAndCancellation() {
    for granted in [false, true] {
      weak var retained: SyntheticPermission?
      let access = CalendarAccess(
        status: { granted },
        factory: {
          let store = SyntheticPermission(); retained = store; return store
        })
      var result: Bool?
      access.request {
        result = $0; XCTAssertFalse(access.requesting)
      }
      XCTAssertTrue(access.requesting); retained?.finish(granted)
      XCTAssertEqual(result, granted); XCTAssertNil(retained)
    }
    let store = SyntheticPermission()
    let access = CalendarAccess(status: { true }, factory: { store })
    access.request { _ in XCTFail("Cancelled permission callback delivered") }
    access.cancel(); XCTAssertFalse(access.requesting); store.finish(true)
  }
  func testEverySnapshotOwnerReleasesStorageOnCloseChangePauseAndLateDelivery() {
    var original = Snapshot()
    original.storageMetadata.topology = DriveTopology(
      physicalDisks: ["disk0"], physicalStoresByVolume: ["disk5s1": ["disk0"]])
    original.storageMetadata.queriedAt = Date(timeIntervalSince1970: 100)
    for (module, suspended) in [
      (Optional<Module>.none, false), (.network, false), (.storage, true),
    ] {
      // Collector cache, application state, dashboard and a queued late delivery.
      var owners = Array(repeating: original, count: 4)
      for index in owners.indices {
        owners[index].releaseActiveViewState(module: module, suspended: suspended)
      }
      XCTAssertTrue(
        owners.allSatisfy {
          $0.storageMetadata.topology == nil && $0.storageMetadata.queriedAt == nil
            && $0.storageMetadata.drives.isEmpty
        })
    }
    var visible = original; visible.releaseActiveViewState(module: .storage, suspended: false)
    XCTAssertNotNil(visible.storageMetadata.topology)
  }
}
