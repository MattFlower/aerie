import AerieCore
import AppKit
import XCTest
@testable import AerieApp
private final class SyntheticHotKeyDriver: HotKeyDriver {
  var onPress: ((UInt32) -> Void)?
  var onLayoutChange: (() -> Void)?
  var identifiers: [UInt32] = []
  var stopped = false, fail = false
  func register(_ shortcut: KeyboardShortcut, identifier: UInt32) -> Int32 {
    identifiers.append(identifier); return fail ? -9878 : 0
  }
  func stop() { stopped = true; onPress = nil; onLayoutChange = nil }
}
final class KeyboardShortcutsTests: XCTestCase {
  func testNoDefaultRegistrationAndReconfigureIgnoresLateIDsAndReleasesDriver() async {
    await MainActor.run {
      var drivers: [SyntheticHotKeyDriver] = []
      let engine = KeyboardShortcuts(factory: {
        let driver = SyntheticHotKeyDriver(); drivers.append(driver); return driver
      })
      XCTAssertTrue(engine.configure([]).isEmpty); XCTAssertTrue(drivers.isEmpty)
      var received: [Module?] = []
      engine.onPress = { received.append($0.module) }
      XCTAssertTrue(engine.configure([KeyboardShortcut(module: .cpu, key: "C")]).isEmpty)
      let oldCallback = drivers[0].onPress, oldLayoutChange = drivers[0].onLayoutChange,
        oldID = drivers[0].identifiers[0]
      oldCallback?(oldID); XCTAssertEqual(received.count, 1)
      XCTAssertTrue(engine.configure([KeyboardShortcut(module: .memory, key: "M")]).isEmpty)
      XCTAssertTrue(drivers[0].stopped); oldCallback?(oldID); XCTAssertEqual(received.count, 1)
      oldLayoutChange?(); XCTAssertEqual(drivers.count, 2)
      drivers[1].onPress?(drivers[1].identifiers[0]); XCTAssertEqual(received.last!, .memory)
      XCTAssertTrue(engine.configure([]).isEmpty); XCTAssertTrue(drivers[1].stopped)
      oldCallback?(oldID); XCTAssertEqual(received.count, 2)
      oldLayoutChange?(); XCTAssertEqual(drivers.count, 2)
    }
  }
  func testLayoutChangesRebindAndConflictsRemainUnavailableInsteadOfDispatching() async {
    await MainActor.run {
      var drivers: [SyntheticHotKeyDriver] = []
      let engine = KeyboardShortcuts(factory: {
        let driver = SyntheticHotKeyDriver(); driver.fail = drivers.count == 1;
        drivers.append(driver); return driver
      })
      var failures: [String] = []
      engine.onReconfigured = { failures = $0 }
      engine.onPress = { _ in XCTFail("Unavailable binding fired") }
      XCTAssertTrue(engine.configure([KeyboardShortcut(module: .weather, key: "W")]).isEmpty)
      drivers[0].onLayoutChange?(); XCTAssertTrue(drivers[0].stopped)
      XCTAssertTrue(failures[0].contains("-9878"))
      drivers[1].onPress?(drivers[1].identifiers[0])
      engine.stop(); XCTAssertTrue(drivers[1].stopped)
    }
  }
  func testZoomControlsRefreshFilteredPointsAndKeepExportRangeAvailableWithoutAWindow() async {
    await MainActor.run {
      _ = NSApplication.shared
      let dashboard = DashboardController(); _ = dashboard.view
      for i in 0..<100 {
        dashboard.history.append(
          .init(date: Date(timeIntervalSince1970: Double(i)), values: ["cpu": Double(i)]))
      }
      dashboard.zoomPicker.selectItem(at: 1); dashboard.historyPosition.doubleValue = 1;
      dashboard.refresh()
      XCTAssertEqual(dashboard.displayedHistory.count, 50)
      XCTAssertEqual(dashboard.canvas.points.count, 50)
      XCTAssertTrue(dashboard.historyPosition.isEnabled)
      dashboard.zoomPicker.selectItem(at: 0); dashboard.refresh()
      XCTAssertEqual(dashboard.displayedHistory.count, 100)
      XCTAssertFalse(dashboard.historyPosition.isEnabled)
      dashboard.show(.weather); XCTAssertTrue(dashboard.zoomPicker.isHidden)
    }
  }
}
