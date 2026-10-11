import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class MenuPanelTests: XCTestCase {
  func testDashboardReleasesItsNativeHierarchyAndRebuildsWithoutLosingSelections() async {
    await MainActor.run {
      _ = NSApplication.shared
      let controller = DashboardController()
      weak var root: NSView?
      weak var scroll: NSScrollView?
      autoreleasepool {
        root = controller.view
        scroll = controller.canvas.enclosingScrollView
        controller.windowPicker.selectItem(at: 2)
        controller.zoomPicker.selectItem(at: 2)
        controller.historyPosition.doubleValue = 0.3
        controller.releasePresentation()
      }
      XCTAssertFalse(controller.isPresentationLoaded); XCTAssertNil(root); XCTAssertNil(scroll)
      XCTAssertNil(controller.canvas.superview)
      for _ in 0..<3 {
        controller.show(.sensors)
        XCTAssertEqual(controller.modules.numberOfItems, Module.allCases.count)
        XCTAssertEqual(controller.windowPicker.numberOfItems, 3)
        XCTAssertEqual(controller.windowPicker.indexOfSelectedItem, 2)
        XCTAssertEqual(controller.zoomPicker.numberOfItems, 4)
        XCTAssertEqual(controller.zoomPicker.indexOfSelectedItem, 2)
        XCTAssertEqual(controller.historyPosition.doubleValue, 0.3)
        XCTAssertNotNil(controller.canvas.enclosingScrollView)
        controller.releasePresentation()
      }
    }
  }
  func testMapTeardownDetachesContentEvenWhenAnOutstandingOwnerRetainsTheController() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var configuration = WeatherConfiguration()
      configuration.mapsEnabled = true; configuration.name = "Synthetic fixture"
      configuration.latitude = 40; configuration.longitude = -100
      var controller: WeatherMapWindowController!
      weak var content: NSView?
      try autoreleasepool {
        controller = try WeatherMapWindowController(configuration: configuration)
        content = controller.window?.contentView
        XCTAssertNotNil(content)
        controller.releaseResources()
      }
      XCTAssertNil(controller.window?.contentView); XCTAssertNil(content)
      controller.releaseResources()
    }
  }
  func testClosedSettingsAndDetailWindowsDetachTheirNativeContent() async {
    await MainActor.run {
      _ = NSApplication.shared
      let settings = PreferencesController(settings: .init())
      let detail = WeatherDetailWindow(title: "Synthetic detail", message: "Fixture")
      settings.windowWillClose(
        Notification(name: NSWindow.willCloseNotification, object: settings.window))
      detail.windowWillClose(
        Notification(name: NSWindow.willCloseNotification, object: detail.window))
      XCTAssertNil(settings.window?.contentView)
      XCTAssertNil(detail.window?.contentView)
    }
  }
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
