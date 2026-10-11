import AppKit
import Carbon
import XCTest
@testable import AerieApp

final class LaunchPresentationTests: XCTestCase {
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
