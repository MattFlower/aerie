import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class RedesignPreferencesTests: XCTestCase {
  @MainActor private func button(_ title: String, in controls: [NSView]) throws -> NSButton {
    try XCTUnwrap(controls.compactMap { $0 as? NSButton }.first { $0.title == title })
  }
  @MainActor private func popup(_ title: String, in controls: [NSView]) throws -> NSPopUpButton {
    try XCTUnwrap(
      controls.compactMap { $0 as? NSPopUpButton }.first { $0.accessibilityLabel() == title })
  }
  @MainActor private func field(_ title: String, in controls: [NSView]) throws -> NSTextField {
    try XCTUnwrap(
      controls.compactMap { $0 as? NSTextField }.first { $0.accessibilityLabel() == title })
  }
  func testInterfacePickerPreservesAllNoneSelectedAndMissingSavedIDs() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var settings = Settings(); settings.networkInterfaces = ["en9"]
      let sample = InterfaceData(
        name: "en0", active: true, addresses: "", received: 0, sent: 0, errors: 0)
      let controller = PreferencesController(
        settings: settings, interfaces: [sample],
        interfaceDescriptions: ["en0": InterfaceDescription(name: "Synthetic Wi-Fi", kind: "Wi-Fi")]
      )
      defer { controller.close() }
      let controls = try preferenceControls(controller)
      let all = try button("Aggregate all active interfaces", in: controls)
      let live = try button("Synthetic Wi-Fi · en0 · Wi-Fi · Active", in: controls)
      let missing = try button("en9 · Not currently available", in: controls)
      let apply = try button("Apply", in: controls); var saved: Settings?
      controller.onApply = { saved = $0 }; apply.performClick(nil)
      XCTAssertEqual(saved?.networkInterfaces, ["en9"])
      missing.performClick(nil); apply.performClick(nil);
      XCTAssertEqual(saved?.networkInterfaces, [])
      live.performClick(nil); apply.performClick(nil);
      XCTAssertEqual(saved?.networkInterfaces, ["en0"])
      all.performClick(nil); apply.performClick(nil); XCTAssertNil(saved?.networkInterfaces)
      XCTAssertFalse(live.isEnabled); XCTAssertFalse(missing.isEnabled)
      XCTAssertFalse(controller.window?.isVisible ?? true)
    }
  }
  func testDateExampleRespondsToFormatEditAndAutomaticMode() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = PreferencesController(settings: Settings()); defer { controller.close() }
      let controls = try preferenceControls(controller)
      let mode = try popup("Date and time format", in: controls),
        format = try field("Date format", in: controls)
      let preview = try field("Date format example", in: controls)
      XCTAssertFalse(format.isEnabled); XCTAssertFalse(preview.stringValue.isEmpty)
      mode.selectItem(withTitle: "Custom format"); _ = mode.sendAction(mode.action, to: mode.target)
      format.stringValue = "'Synthetic preview' yyyy";
      controller.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: format))
      XCTAssertTrue(format.isEnabled);
      XCTAssertTrue(preview.stringValue.hasPrefix("Synthetic preview "))
      var saved: Settings?; controller.onApply = { saved = $0 }
      let apply = try button("Apply", in: controls); apply.performClick(nil)
      XCTAssertEqual(saved?.clockFormat, "'Synthetic preview' yyyy")
      mode.selectItem(withTitle: "Follow Mac settings");
      _ = mode.sendAction(mode.action, to: mode.target)
      apply.performClick(nil); XCTAssertEqual(saved?.clockFormat, "");
      XCTAssertFalse(format.isEnabled)
    }
  }
  func testSensorPickerAndAdvancedRangePreserveRuleIdentityAndNativeUnits() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var settings = Settings()
      var first = ThresholdRule(metric: "download", threshold: 20_000_000, duration: 10)
      first.enabled = false
      let second = ThresholdRule(metric: "cpu", threshold: 80, duration: 30)
      settings.rules = [first, second]
      let controller = PreferencesController(
        settings: settings,
        sensors: [SensorData(key: "Tp09", label: "CPU efficiency sensor 1", value: 35, unit: "°C")]);
      defer { controller.close() }
      let controls = try preferenceControls(controller)
      let savedRules = try popup("Saved value notifications", in: controls)
      savedRules.selectItem(at: 1);
      _ = savedRules.sendAction(savedRules.action, to: savedRules.target)
      XCTAssertEqual(try field("Limit", in: controls).stringValue, "20.0")
      try field("Limit", in: controls).stringValue = "25"
      try button("Update Draft", in: controls).performClick(nil)
      var applied: Settings?; controller.onApply = { applied = $0 };
      let apply = try button("Apply", in: controls); apply.performClick(nil)
      XCTAssertEqual(applied?.rules.map(\.id), [first.id, second.id]);
      XCTAssertFalse(applied?.rules[0].enabled ?? true)
      XCTAssertEqual(applied?.rules[0].threshold, 25_000_000)
      let metric = try popup("Notify me when", in: controls);
      metric.selectItem(withTitle: "Individual sensor");
      _ = metric.sendAction(metric.action, to: metric.target)
      let sensor = try popup("Choose a sensor", in: controls); sensor.selectItem(at: 1);
      _ = sensor.sendAction(sensor.action, to: sensor.target)
      XCTAssertEqual(try field("Sensor code (4 characters)", in: controls).stringValue, "Tp09")
      XCTAssertEqual(try popup("Sensor native unit", in: controls).titleOfSelectedItem, "°C")
      XCTAssertTrue(
        try field("Notification example", in: controls).stringValue.contains(
          "CPU efficiency sensor 1"))
      let condition = try popup("Condition", in: controls);
      condition.selectItem(withTitle: "Inside range (inclusive)");
      _ = condition.sendAction(condition.action, to: condition.target)
      XCTAssertEqual(try button("Show advanced notification options", in: controls).state, .on)
      XCTAssertTrue(try field("Upper bound (ranges only)", in: controls).isEnabled)
      try field("Limit", in: controls).stringValue = "20";
      try field("Upper bound (ranges only)", in: controls).stringValue = "40"
      try button("Add to Draft", in: controls).performClick(nil); apply.performClick(nil)
      XCTAssertEqual(applied?.rules.last?.metric, "sensor:Tp09");
      XCTAssertEqual(applied?.rules.last?.threshold, 20);
      XCTAssertEqual(applied?.rules.last?.sensorUnit, "°C")
    }
  }
  func testVirtualSensorListRenamesAndRestoresWithoutLosingMissingAliases() async throws {
    try await MainActor.run {
      let list = SensorNameList(
        sensors: [
          SensorData(key: "Tp09", label: "CPU efficiency sensor 1", value: nil, unit: "°C")
        ], names: ["Gone": "Saved missing sensor"])
      let table = try XCTUnwrap(preferenceViews(list).compactMap { $0 as? NSTableView }.first)
      let editor = try XCTUnwrap(
        list.tableView(table, viewFor: table.tableColumns[0], row: 0) as? NSTextField)
      var names: [String: String]? = ["Gone": "Saved missing sensor"]
      list.onNameChanged = { key, alias in
        names?[key] = alias; return true
      }
      editor.stringValue = "Local processor sensor";
      list.controlTextDidEndEditing(
        Notification(name: NSControl.textDidEndEditingNotification, object: editor))
      XCTAssertEqual(names?["Tp09"], "Local processor sensor");
      XCTAssertEqual(names?["Gone"], "Saved missing sensor")
      editor.stringValue = "";
      list.controlTextDidEndEditing(
        Notification(name: NSControl.textDidEndEditingNotification, object: editor))
      XCTAssertNil(names?["Tp09"]); XCTAssertEqual(editor.stringValue, "CPU efficiency sensor 1");
      XCTAssertEqual(names?["Gone"], "Saved missing sensor")
      XCTAssertNil(list.window)
    }
  }
  func testMenuSpacingControlsExplainWhichLayoutOwnsEachChoice() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = PreferencesController(settings: Settings()); defer { controller.close() }
      let controls = try preferenceControls(controller)
      let layout = try popup("Menu-bar layout", in: controls)
      let padding = try popup("Padding inside each module", in: controls)
      let gap = try popup("Gap between grouped modules", in: controls)
      let compact = try button("Compact spacing in combined dashboard", in: controls)
      XCTAssertTrue(padding.isEnabled); XCTAssertTrue(gap.isEnabled);
      XCTAssertFalse(compact.isEnabled)
      layout.selectItem(withTitle: "Separate items");
      _ = layout.sendAction(layout.action, to: layout.target)
      XCTAssertTrue(padding.isEnabled); XCTAssertFalse(gap.isEnabled);
      XCTAssertFalse(compact.isEnabled)
      layout.selectItem(withTitle: "Combined dashboard");
      _ = layout.sendAction(layout.action, to: layout.target)
      XCTAssertFalse(padding.isEnabled); XCTAssertFalse(gap.isEnabled);
      XCTAssertTrue(compact.isEnabled)
      XCTAssertFalse(controller.window?.isVisible ?? true)
    }
  }

}
