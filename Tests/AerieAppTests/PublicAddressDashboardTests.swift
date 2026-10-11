import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class PublicAddressDashboardTests: XCTestCase {
  func testReleasedExternalAddressIsRemovedFromNativeCopiedRowsOffWindow() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let dashboard = DashboardController(); _ = dashboard.view
      dashboard.settings.publicAddress = true; dashboard.show(.network)
      let reading = try PublicAddressReading.parse(
        Data("{\"ip\":\"203.0.113.7\"}".utf8), date: Date(timeIntervalSince1970: 1_700_000_000))
      dashboard.updatePublicAddress(reading, status: "Synthetic updated"); dashboard.refresh()
      @MainActor func containsAddress() -> Bool {
        dashboard.canvas.rows.contains { row in
          if case .metric(_, let value) = row { return value == reading.address }
          return false
        }
      }
      XCTAssertTrue(containsAddress())
      dashboard.updatePublicAddress(nil, status: "Public IP lookup is paused")
      XCTAssertNil(dashboard.publicAddress); XCTAssertFalse(containsAddress())
      dashboard.updatePublicAddress(reading, status: "Synthetic updated"); dashboard.refresh()
      XCTAssertTrue(containsAddress())
      dashboard.settings.publicAddress = nil
      dashboard.updatePublicAddress(nil, status: "Public IP lookup is off")
      XCTAssertFalse(containsAddress()); XCTAssertNil(dashboard.publicAddress)
    }
  }
}
