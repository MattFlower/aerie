import AerieCore
import AppKit
import XCTest
@testable import AerieApp

private final class SyntheticWiFiPermission: WiFiPermissionRequest {
  var calls = 0, closes = 0
  var callback: ((WiFiAuthorization) -> Void)?
  func request(_ completion: @escaping (WiFiAuthorization) -> Void) {
    calls += 1; callback = completion
  }
  func close() { closes += 1 }
  func finish(_ status: WiFiAuthorization) { callback?(status) }
}
final class WiFiAccessTests: XCTestCase {
  func testNoAllocationWithoutExplicitForegroundRequestOrForDecidedAccess() async {
    await MainActor.run {
      var allocations = 0, status = WiFiAuthorization.notDetermined
      let access = WiFiAccess(
        status: { status },
        factory: {
          allocations += 1; return SyntheticWiFiPermission()
        })
      XCTAssertFalse(access.requesting); XCTAssertEqual(allocations, 0)
      access.request(foreground: false) {
        guard case .failure(.requiresForeground) = $0 else {
          return XCTFail("Expected foreground gate")
        }
      }
      for decided in [
        WiFiAuthorization.authorized, .denied, .restricted, .servicesDisabled, .unknown,
      ] {
        status = decided
        access.request(foreground: true) {
          guard case .success(let value) = $0 else { return XCTFail("Expected existing status") }
          XCTAssertEqual(value, decided)
        }
      }
      XCTAssertEqual(allocations, 0)
    }
  }
  func testGrantDenialRestrictionAndCancellationReleaseRequestsAndRejectLateCallbacks() async {
    await MainActor.run {
      for terminal in [WiFiAuthorization.authorized, .denied, .restricted, .servicesDisabled] {
        var status = WiFiAuthorization.notDetermined
        weak var retained: SyntheticWiFiPermission?
        let access = WiFiAccess(
          status: { status },
          factory: {
            let source = SyntheticWiFiPermission(); retained = source; return source
          })
        var result: WiFiAuthorization?
        access.request(foreground: true) {
          if case .success(let value) = $0 { result = value }
          XCTAssertFalse(access.requesting)
        }
        retained?.finish(.notDetermined); XCTAssertTrue(access.requesting); XCTAssertNil(result)
        status = terminal; retained?.finish(terminal)
        XCTAssertEqual(result, terminal); XCTAssertNil(retained)
      }
      var status = WiFiAuthorization.notDetermined, allocations = 0
      weak var retained: SyntheticWiFiPermission?
      let access = WiFiAccess(
        status: { status },
        factory: {
          let source = SyntheticWiFiPermission(); retained = source; allocations += 1; return source
        })
      access.request(foreground: true) { _ in XCTFail("Cancelled callback delivered") }
      let late = retained?.callback
      access.request(foreground: true) {
        guard case .failure(.alreadyRequesting) = $0 else {
          return XCTFail("Expected pending gate")
        }
      }
      XCTAssertEqual(allocations, 1)
      access.cancel(); XCTAssertNil(retained); XCTAssertFalse(access.requesting)
      late?(.authorized)
      access.request(foreground: true) { _ in XCTFail("Old generation delivered into new request") }
      status = .authorized; late?(.authorized); XCTAssertTrue(access.requesting)
      access.cancel(); XCTAssertNil(retained)
    }
  }
  func testNativePermissionButtonOnlyInvokesInjectedActionOffWindow() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = PreferencesController(settings: Settings())
      defer { controller.close() }
      let tabs = try XCTUnwrap(
        controller.window?.contentView?.subviews.compactMap { $0 as? NSTabView }.first)
      @MainActor func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
      }
      let controls = tabs.tabViewItems.compactMap(\.view).flatMap { descendants($0) }
      let button = try XCTUnwrap(
        controls.compactMap { $0 as? NSButton }.first { $0.title == "Allow Wi-Fi Identity…" })
      var calls = 0; controller.onWiFiPermission = { calls += 1 }
      XCTAssertEqual(calls, 0); button.performClick(nil); XCTAssertEqual(calls, 1)
      XCTAssertFalse(controller.window?.isVisible ?? true)
    }
  }
  func testNativeDashboardReleasesCopiedIdentityRowsOffWindow() async {
    await MainActor.run {
      _ = NSApplication.shared
      let dashboard = DashboardController(); _ = dashboard.view
      dashboard.snapshot.wifi = WiFiReading(
        interface: "en0", powered: true, ssid: "Synthetic identity", authorization: .authorized)
      dashboard.show(.network)
      @MainActor func hasIdentity() -> Bool {
        dashboard.canvas.rows.contains {
          if case .metric(_, let value) = $0 { return value == "Synthetic identity" }
          return false
        }
      }
      XCTAssertTrue(hasIdentity()); dashboard.releaseWiFi()
      XCTAssertNil(dashboard.snapshot.wifi); XCTAssertFalse(hasIdentity())
    }
  }
}
