import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class SensorPreferencesTests: XCTestCase {
  func testNativeRuleAndAliasControlsApplyUnitIdentityAndPreserveEditsOffWindow() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = PreferencesController(settings: Settings())
      defer { controller.close() }
      let content = try XCTUnwrap(controller.window?.contentView)
      let tabs = try XCTUnwrap(content.subviews.compactMap { $0 as? NSTabView }.first)
      @MainActor func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
      }
      let controls = tabs.tabViewItems.compactMap(\.view).flatMap { descendants($0) }
      @MainActor func field(_ label: String) throws -> NSTextField {
        try XCTUnwrap(
          controls.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == label })
      }
      @MainActor func popup(_ label: String) throws -> NSPopUpButton {
        try XCTUnwrap(
          controls.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == label })
      }
      let metric = try popup("Metric"), key = try field("Sensor firmware key (4 chars)")
      let unit = try popup("Sensor native unit")
      XCTAssertFalse(key.isEnabled); XCTAssertFalse(unit.isEnabled)
      metric.selectItem(withTitle: "Individual sensor")
      _ = metric.sendAction(metric.action, to: metric.target)
      XCTAssertTrue(key.isEnabled); XCTAssertTrue(unit.isEnabled)
      key.stringValue = "F0Ac"; unit.selectItem(withTitle: "rpm")
      try field("Threshold").stringValue = "2000"
      let add = try XCTUnwrap(controls.compactMap { $0 as? NSButton }.first { $0.title == "Add" })
      add.performClick(nil)
      let names = try XCTUnwrap(
        controls.compactMap { $0 as? NSTextView }.first {
          $0.accessibilityLabel() == "Local sensor names by firmware key"
        })
      names.string = "F0Ac | Exhaust fan"
      let addressConsent = try XCTUnwrap(
        controls.compactMap { $0 as? NSButton }.first {
          $0.title == "Allow public IP lookup through ipify"
        })
      XCTAssertEqual(addressConsent.state, .off); addressConsent.state = .on
      var applied: Settings?
      controller.onApply = { applied = $0 }
      let apply = try XCTUnwrap(
        content.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Apply" })
      apply.performClick(nil)
      XCTAssertEqual(applied?.publicAddress, true)
      let first = try XCTUnwrap(applied?.rules.first)
      XCTAssertEqual(first.metric, "sensor:F0Ac"); XCTAssertEqual(first.sensorUnit, "rpm")
      XCTAssertEqual(applied?.sensorNames, ["F0Ac": "Exhaust fan"])
      let toggle = try XCTUnwrap(
        controls.compactMap { $0 as? NSButton }.first { $0.title == "Enable/Disable" })
      toggle.performClick(nil)
      try field("Threshold").stringValue = "3000"
      let save = try XCTUnwrap(
        controls.compactMap { $0 as? NSButton }.first { $0.title == "Save Selected" })
      save.performClick(nil); apply.performClick(nil)
      XCTAssertEqual(applied?.rules.first?.id, first.id)
      XCTAssertEqual(applied?.rules.first?.enabled, false)
      XCTAssertEqual(applied?.rules.first?.threshold, 3000)
      names.string = "F0Ac | One\nF0Ac | Duplicate"
      applied = nil; apply.performClick(nil); XCTAssertNil(applied)
      XCTAssertFalse(controller.window?.isVisible ?? true)
    }
  }
}
