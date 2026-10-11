import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class SettingsLifecycleTests: XCTestCase {
  private final class Provider: LocationLookupProvider {
    var cancelled = 0
    var callback: ((Result<[LocationChoice], LocationLookupError>) -> Void)?
    func macLocation(
      foreground: Bool,
      completion: @escaping (Result<[LocationChoice], LocationLookupError>) -> Void
    ) { callback = completion }
    func search(
      _ query: String, completion: @escaping (Result<[LocationChoice], LocationLookupError>) -> Void
    ) { callback = completion }
    func cancel() { cancelled += 1 }
  }
  func testThreeHiddenSettingsRebuildCloseCyclesReleaseOwnersAndRejectLateLookups() async {
    await MainActor.run {
      _ = NSApplication.shared
      for _ in 0..<3 {
        weak var releasedController: PreferencesController?
        weak var releasedContent: NSView?
        weak var replacedContent: NSView?
        let provider = Provider(); var applications = 0, deliveries = 0
        autoreleasepool {
          var controller: PreferencesController? = PreferencesController(
            settings: Settings(),
            interfaces: [
              InterfaceData(
                name: "en0", active: true, addresses: "", received: 0, sent: 0, errors: 0)
            ],
            sensors: [
              SensorData(key: "Tp09", label: "Synthetic processor sensor", value: 35, unit: "°C")
            ])
          releasedController = controller; replacedContent = controller?.window?.contentView
          controller?.onApply = { _ in applications += 1 }
          controller?.onProfileReview = { _ in true }
          controller?.locationSession = LocationLookupSession { provider }
          controller?.locationSession.search("Synthetic city") { _ in deliveries += 1 }
          XCTAssertTrue(controller?.reviewAndStage(.defaults(preservingHistory: false)) == true)
          XCTAssertFalse(controller?.locationSession.isPending ?? true)
          provider.callback?(.failure(.timeout)); XCTAssertEqual(deliveries, 0)
          XCTAssertFalse(controller?.window?.isVisible ?? true)
          releasedContent = controller?.window?.contentView
          controller?.locationSession.search("Synthetic city") { _ in deliveries += 1 }
          controller?.close()
          XCTAssertNil(controller?.window?.contentView);
          XCTAssertNil(controller?.window?.contentViewController)
          provider.callback?(.failure(.timeout)); controller = nil
        }
        XCTAssertNil(releasedController); XCTAssertNil(replacedContent);
        XCTAssertNil(releasedContent)
        XCTAssertEqual(applications, 0); XCTAssertEqual(deliveries, 0);
        XCTAssertGreaterThanOrEqual(provider.cancelled, 2)
      }
    }
  }
}
