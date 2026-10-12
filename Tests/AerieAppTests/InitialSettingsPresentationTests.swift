import XCTest
@testable import AerieApp

final class InitialSettingsPresentationTests: XCTestCase {
  func testFirstSampleFulfillsOnePendingLaunchWithoutWaitingForAnotherInterval() {
    var presentation = InitialSettingsPresentation()
    XCTAssertFalse(presentation.request())
    XCTAssertFalse(presentation.request())
    XCTAssertTrue(presentation.receivedSample())
    XCTAssertFalse(presentation.receivedSample())
    XCTAssertFalse(presentation.fallback())
    XCTAssertTrue(presentation.request())
  }
  func testBoundedFallbackPresentsOnceAndLateSampleDoesNotReopenClosedSettings() {
    var presentation = InitialSettingsPresentation()
    XCTAssertFalse(presentation.request())
    XCTAssertTrue(presentation.fallback())
    XCTAssertFalse(presentation.fallback())
    XCTAssertFalse(presentation.receivedSample())
    XCTAssertTrue(presentation.request())
  }
  func testAnExplicitPresentationCancelsPendingLaunchAndSilentStartupHasNoRequest() {
    var presentation = InitialSettingsPresentation()
    XCTAssertFalse(presentation.receivedSample())
    var pending = InitialSettingsPresentation()
    XCTAssertFalse(pending.request())
    pending.didPresent()
    XCTAssertFalse(pending.fallback())
    XCTAssertFalse(pending.receivedSample())
    XCTAssertTrue(pending.request())
  }
}
