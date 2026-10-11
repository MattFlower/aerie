import AppKit
import Carbon
import XCTest
@testable import AerieApp

final class LaunchPresentationTests: XCTestCase {
  func testExplicitInitialSettingsDoesNotEnableBackgroundReopenOrSelfCheckUI() {
    let arguments = ["Aerie", "--background", "--open-settings"]
    XCTAssertFalse(LaunchPresentation.silent(arguments: arguments, event: nil))
    XCTAssertFalse(
      LaunchPresentation.presentsOnReopen(
        arguments: arguments, visibleWindows: false, menuShown: false))
    XCTAssertTrue(
      LaunchPresentation.silent(arguments: arguments + ["--self-check"], event: nil))
  }
  func testManualReopenPresentsOnlyWhenNoExistingPresentation() {
    XCTAssertTrue(
      LaunchPresentation.presentsOnReopen(
        arguments: ["Aerie"], visibleWindows: false, menuShown: false))
    for (windows, menu) in [(true, false), (false, true), (true, true)] {
      XCTAssertFalse(
        LaunchPresentation.presentsOnReopen(
          arguments: ["Aerie"], visibleWindows: windows, menuShown: menu))
    }
  }
  func testExplicitBackgroundAndSelfCheckReopensStayQuiet() {
    for argument in ["--background", "--self-check"] {
      XCTAssertFalse(
        LaunchPresentation.presentsOnReopen(
          arguments: ["Aerie", argument], visibleWindows: false, menuShown: false))
    }
    // System launch markers affect startup, not a later explicit manual reopen.
    XCTAssertTrue(
      LaunchPresentation.presentsOnReopen(
        arguments: ["Aerie", "unrelated-option"], visibleWindows: false, menuShown: false))
  }
  func testManualLaunchAndSilentArgumentsOrSystemMarkersRemainDistinct() {
    XCTAssertFalse(LaunchPresentation.silent(arguments: ["Aerie"], event: nil))
    for argument in ["--background", "--self-check"] {
      XCTAssertTrue(LaunchPresentation.silent(arguments: ["Aerie", argument], event: nil))
    }
    for marker in [AEKeyword(keyAELaunchedAsLogInItem), AEKeyword(keyAELaunchedAsServiceItem)] {
      let event = NSAppleEventDescriptor(
        eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
        targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID))
      event.setParam(NSAppleEventDescriptor(boolean: true), forKeyword: marker)
      XCTAssertTrue(LaunchPresentation.silent(arguments: ["Aerie"], event: event))
      let encoded = NSAppleEventDescriptor(
        eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
        targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID))
      encoded.setParam(
        NSAppleEventDescriptor(enumCode: marker), forKeyword: AEKeyword(keyAEPropData))
      XCTAssertTrue(LaunchPresentation.silent(arguments: ["Aerie"], event: encoded))
    }
  }
}
