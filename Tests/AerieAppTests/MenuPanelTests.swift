import AppKit
import XCTest
@testable import AerieApp

final class MenuPanelTests: XCTestCase {
  func testClosedNativeContentDetachesWhileTheReusableControllerSurvives() async {
    await MainActor.run {
      _ = NSApplication.shared
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 416, height: 620), styleMask: [],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let controller = NSViewController()
      controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 416, height: 620))
      window.contentViewController = controller
      XCTAssertTrue(controller.view.window === window)
      MenuPanel.releaseContent(of: window)
      XCTAssertNil(window.contentViewController)
      XCTAssertNil(controller.view.window)
      XCTAssertNil(controller.view.superview)
      window.contentViewController = controller
      XCTAssertTrue(controller.view.window === window)
      MenuPanel.releaseContent(of: window)
    }
  }
  func testMissingStatusWindowUsesTheSelectedScreenWithoutDroppingTheDashboard() {
    let screen = NSRect(x: -2000, y: 300, width: 1800, height: 1000)
    let anchor = MenuPanel.anchor(attached: nil, visibleFrame: screen)
    XCTAssertEqual(anchor.midX, screen.midX)
    XCTAssertEqual(anchor.minY, screen.maxY)
    let attached = NSRect(x: -1700, y: 1310, width: 40, height: 24)
    XCTAssertEqual(MenuPanel.anchor(attached: attached, visibleFrame: screen), attached)
  }
  func testAnchoringStaysInTheSelectedScreenIncludingNegativeMonitorCoordinates() {
    let screen = NSRect(x: -2000, y: 300, width: 1800, height: 1000)
    let size = NSSize(width: 416, height: 642)
    for x in [-2200.0, -1900, -1000, 100] {
      let point = MenuPanel.origin(
        anchor: NSRect(x: x, y: 1300, width: 80, height: 24), visibleFrame: screen, size: size)
      XCTAssertGreaterThanOrEqual(point.x, screen.minX + 8)
      XCTAssertLessThanOrEqual(point.x + size.width, screen.maxX - 8)
      XCTAssertGreaterThanOrEqual(point.y, screen.minY + 8)
      XCTAssertLessThanOrEqual(point.y + size.height, screen.maxY - 8)
    }
    let center = MenuPanel.origin(
      anchor: NSRect(x: -1200, y: 1300, width: 80, height: 24), visibleFrame: screen, size: size)
    XCTAssertEqual(center.x + size.width / 2, -1160)
  }
  func testClosedPanelHasNoWindowAndRepeatedCloseDoesNotDeliverSpuriousLifecycleEvents() {
    let panel = MenuPanel()
    var closes = 0
    panel.onClose = { closes += 1 }
    XCTAssertFalse(panel.isShown)
    panel.performClose(nil); panel.performClose(nil)
    panel.windowWillClose(Notification(name: NSWindow.willCloseNotification))
    XCTAssertEqual(closes, 0); XCTAssertFalse(panel.isShown)
  }
}
