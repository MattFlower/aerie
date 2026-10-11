import XCTest
@testable import AerieApp

final class IdleMemoryReclaimerTests: XCTestCase {
  func testRepeatedClosuresCoalesceAndOpeningCancelsPendingWork() {
    var work: [() -> Void] = [], releases = 0
    let reclaimer = IdleMemoryReclaimer(
      hasPresentation: { false }, schedule: { _, callback in work.append(callback) },
      release: { complete in
        releases += 1; complete(42, 0.001)
      })
    reclaimer.presentationClosed(); reclaimer.presentationClosed()
    work[0](); XCTAssertEqual(releases, 0)
    reclaimer.presentationOpened(); work[1](); XCTAssertEqual(releases, 0)
    reclaimer.presentationClosed(); work[2](); XCTAssertEqual(releases, 1)
  }
  func testMinimizedOrOtherNativePresentationBlocksAndRequestsAreSpaced() {
    var now = 100.0, presented = true, delays: [Double] = [], work: [() -> Void] = []
    var completions: [(UInt64, Double)] = []
    let reclaimer = IdleMemoryReclaimer(
      clock: { now }, hasPresentation: { presented },
      schedule: { delay, callback in
        delays.append(delay); work.append(callback)
      },
      release: { complete in complete(99, 0.002) })
    reclaimer.onComplete = { completions.append(($0, $1)) }
    reclaimer.presentationClosed(); work[0](); XCTAssertTrue(completions.isEmpty)
    presented = false; reclaimer.presentationClosed(); now = 101; work[1]()
    XCTAssertEqual(completions.first?.0, 99)
    now = 106; reclaimer.presentationClosed(); XCTAssertEqual(delays.last, 15)
    now = 121; work[2](); XCTAssertEqual(completions.count, 2)
  }
  func testPendingWorkDoesNotKeepTheReclaimerAlive() {
    var work: (() -> Void)?
    weak var owner: IdleMemoryReclaimer?
    var reclaimer: IdleMemoryReclaimer? = IdleMemoryReclaimer(
      hasPresentation: { false }, schedule: { _, callback in work = callback },
      release: { _ in XCTFail("Cancelled owner must not perform work") })
    owner = reclaimer; reclaimer?.presentationClosed(); reclaimer = nil
    XCTAssertNil(owner); work?()
  }
}
