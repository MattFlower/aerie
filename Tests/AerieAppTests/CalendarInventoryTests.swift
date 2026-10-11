import AerieCore
import Foundation
import XCTest
@testable import AerieApp

private final class SyntheticInventorySource: CalendarInventorySource {
  var inventory = CalendarInventory(items: [
    EventCalendarItem(identifier: "fixture", title: "Fixture")
  ])
  var beforeRead: (() -> Void)?
  var closed = false
  func read() -> CalendarInventory {
    XCTAssertFalse(Thread.isMainThread); beforeRead?(); return inventory
  }
  func close() { XCTAssertFalse(Thread.isMainThread); closed = true }
}
private final class InventoryAccessState {
  private let lock = NSLock()
  private var value = true
  var authorized: Bool { lock.lock(); defer { lock.unlock() }; return value }
  func revoke() { lock.lock(); value = false; lock.unlock() }
}
private final class FilterFixtureSource: CalendarEventSource {
  var selection: [String]?
  var configured = false, closed = false
  var unavailableCalendars: Int { selection?.contains("missing-fixture") == true ? 1 : 0 }
  func configure(calendars: [String]?) {
    XCTAssertFalse(Thread.isMainThread); selection = calendars; configured = true
  }
  func enumerate(
    range: DateInterval, cancelled: @escaping () -> Bool,
    visit: @escaping (CalendarEventRecord) -> Bool
  ) {
    XCTAssertTrue(configured)
    for identifier in ["fixture-first", "fixture-second"]
    where selection?.contains(identifier) ?? true {
      if cancelled() { return }
      if !visit(CalendarEventRecord(start: range.start, end: range.end, title: identifier)) {
        return
      }
    }
  }
  func close() { closed = true }
}
final class CalendarInventoryTests: XCTestCase {
  func testSelectionReachesWorkerSourceAndNoEventsNeverCreatesAStore() async {
    let access = CalendarAccess(status: { true })
    var sources: [FilterFixtureSource] = []
    let reader = CalendarEventReader(
      access: access,
      factory: {
        let source = FilterFixtureSource(); sources.append(source); return source
      })
    let range = DateInterval(start: Date(timeIntervalSince1970: 100), duration: 100)
    let filtered = expectation(description: "filtered")
    reader.load(ranges: [range], calendars: ["fixture-second", "missing-fixture"]) { result in
      XCTAssertEqual(result.ranges[0].events.map(\.title), ["fixture-second"])
      XCTAssertEqual(result.unavailableCalendars, 1); XCTAssertTrue(sources[0].closed);
      filtered.fulfill()
    }
    await fulfillment(of: [filtered], timeout: 2)
    let none = expectation(description: "none")
    reader.load(ranges: [range], calendars: []) { result in
      XCTAssertTrue(result.ranges[0].events.isEmpty); XCTAssertEqual(sources.count, 1);
      none.fulfill()
    }
    await fulfillment(of: [none], timeout: 2)
    let all = expectation(description: "all")
    reader.load(ranges: [range]) { result in
      XCTAssertEqual(result.ranges[0].events.count, 2); XCTAssertNil(sources[1].selection);
      all.fulfill()
    }
    await fulfillment(of: [all], timeout: 2)
  }
  func testDeniedInventoryNeverCreatesPermissionOrEventStoreAndCopiesReleaseBeforeDelivery() async {
    let denied = CalendarInventoryReader(
      access: CalendarAccess(
        status: { false },
        factory: {
          XCTFail("Permission must not be requested"); fatalError()
        }),
      factory: {
        XCTFail("Denied source created"); return SyntheticInventorySource()
      })
    let done = expectation(description: "denied")
    denied.load { result in
      XCTAssertTrue(result.denied); XCTAssertTrue(result.items.isEmpty); done.fulfill()
    }
    await fulfillment(of: [done], timeout: 2)
    weak var source: SyntheticInventorySource?
    let allowed = CalendarInventoryReader(
      access: CalendarAccess(status: { true }),
      factory: {
        let value = SyntheticInventorySource(); source = value
        value.inventory.items = [
          EventCalendarItem(identifier: "fixture", title: String(repeating: "t", count: 500))
        ]
        return value
      })
    let copied = expectation(description: "copied")
    allowed.load { result in
      XCTAssertNil(source); XCTAssertEqual(result.items[0].title.count, 128); copied.fulfill()
    }
    await fulfillment(of: [copied], timeout: 2)
  }
  func testRapidReopenCancellationAndRevocationDiscardLateInventory() async {
    let state = InventoryAccessState()
    let access = CalendarAccess(status: { state.authorized })
    let source = SyntheticInventorySource(), started = expectation(description: "started")
    let release = DispatchSemaphore(value: 0)
    source.beforeRead = {
      started.fulfill(); _ = release.wait(timeout: .now() + 2)
    }
    let reader = CalendarInventoryReader(access: access, factory: { source })
    let old = expectation(description: "cancelled callback"); old.isInverted = true
    reader.load { _ in old.fulfill() }
    await fulfillment(of: [started], timeout: 2)
    reader.cancel(); state.revoke()
    let replacement = expectation(description: "replacement denied")
    reader.load { result in
      XCTAssertTrue(result.denied); XCTAssertTrue(result.items.isEmpty);
      XCTAssertTrue(source.closed)
      replacement.fulfill()
    }
    release.signal(); await fulfillment(of: [replacement], timeout: 2)
    await fulfillment(of: [old], timeout: 0.05)
  }
  func testUnboundedDuplicateAndInvalidIdentifiersAreWithheld() async {
    for items in [
      (0..<129).map { EventCalendarItem(identifier: "fixture-\($0)", title: "Fixture") },
      [
        EventCalendarItem(identifier: "fixture", title: "One"),
        EventCalendarItem(identifier: "fixture", title: "Two"),
      ],
      [EventCalendarItem(identifier: "", title: "Invalid")],
    ] {
      let source = SyntheticInventorySource(); source.inventory.items = items
      let reader = CalendarInventoryReader(
        access: CalendarAccess(status: { true }), factory: { source })
      let done = expectation(description: "invalid withheld")
      reader.load { result in
        XCTAssertTrue(result.invalid); XCTAssertTrue(result.items.isEmpty);
        XCTAssertTrue(source.closed); done.fulfill()
      }
      await fulfillment(of: [done], timeout: 2)
    }
  }
}
