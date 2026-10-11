import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class SettingsProfilePreferencesTests: XCTestCase {
  @MainActor private func allViews(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap { allViews($0) }
  }
  @MainActor private func controls(_ controller: PreferencesController) throws -> [NSView] {
    let content = try XCTUnwrap(controller.window?.contentView)
    let tabs = try XCTUnwrap(content.subviews.compactMap { $0 as? NSTabView }.first)
    return allViews(content) + tabs.tabViewItems.compactMap(\.view).flatMap { allViews($0) }
  }
  @MainActor private func button(_ title: String, in controller: PreferencesController) throws
    -> NSButton
  {
    try XCTUnwrap(
      try controls(controller).compactMap { $0 as? NSButton }.first { $0.title == title })
  }
  func testRestoreIsReviewedAndStagedBeforeApplyWithoutInvokingAnyGrant() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var original = Settings(); original.interval = 5; original.processCount = 12
      original.persistentHistory = true; original.sensorSampling = .whenNeeded
      original.sensorNames = ["TC0P": "Synthetic alias"]
      let controller = PreferencesController(settings: original); defer { controller.close() }
      var applied: Settings?, reviews = 0, grants = 0
      controller.onApply = { applied = $0 }
      controller.onNotifications = { grants += 1 }; controller.onCalendar = { grants += 1 }
      controller.onWiFiPermission = { grants += 1 }; controller.onLogin = { grants += 1 }
      controller.onProfileReview = { profile in
        reviews += 1; XCTAssertEqual(profile.kind, .defaults); return true
      }
      try button("Restore Defaults…", in: controller).performClick(nil)
      XCTAssertEqual(reviews, 1); XCTAssertNil(applied); XCTAssertEqual(grants, 0)
      XCTAssertFalse(controller.window?.isVisible ?? true)
      try button("Apply", in: controller).performClick(nil)
      let value = try XCTUnwrap(applied)
      XCTAssertEqual(value.interval, 1); XCTAssertEqual(value.processCount, 5)
      XCTAssertEqual(value.effectiveSensorSampling, .all); XCTAssertNil(value.sensorNames)
      XCTAssertTrue(value.effectivePersistentHistory); XCTAssertEqual(value.eventCalendars, [])
      XCTAssertFalse(value.weather.enabled); XCTAssertFalse(value.weather.mapsEnabled)
      XCTAssertFalse(value.effectivePublicAddress); XCTAssertEqual(grants, 0)
    }
  }
  func testCancellingReviewPreservesUnsavedEditsAndExistingConfiguration() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var original = Settings(); original.interval = 5
      let controller = PreferencesController(settings: original); defer { controller.close() }
      let field = try XCTUnwrap(
        try controls(controller).compactMap { $0 as? NSTextField }.first {
          $0.accessibilityLabel() == "Top process count (1–20)"
        })
      field.stringValue = "7"
      var applied: Settings?; controller.onApply = { applied = $0 }
      controller.onProfileReview = { _ in false }
      try button("Restore Defaults…", in: controller).performClick(nil)
      XCTAssertEqual(field.stringValue, "7"); XCTAssertNil(applied)
      try button("Apply", in: controller).performClick(nil)
      XCTAssertEqual(applied?.processCount, 7); XCTAssertEqual(applied?.interval, 5)
    }
  }
  func testImportedDraftCanBeDiscardedWithoutApplyingAndRebuildsUpdatedControls() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var incoming = Settings(); incoming.processCount = 15; incoming.theme = .dark
      incoming.worldClockStyle = .analog; incoming.weather.enabled = true
      incoming.weather.name = "Synthetic location"; incoming.weather.latitude = 10;
      incoming.weather.longitude = 20
      let profile = try SettingsProfile.imported(
        JSONEncoder().encode(incoming), preservingHistory: false)
      let controller = PreferencesController(settings: Settings())
      var applications = 0; controller.onApply = { _ in applications += 1 }
      controller.onProfileReview = { $0.kind == .imported }
      XCTAssertTrue(controller.reviewAndStage(profile)); XCTAssertEqual(applications, 0)
      let views = try controls(controller)
      XCTAssertEqual(
        views.compactMap { $0 as? NSTextField }.first {
          $0.accessibilityLabel() == "Top process count (1–20)"
        }?.stringValue, "15")
      XCTAssertEqual(
        views.compactMap { $0 as? NSPopUpButton }.first {
          $0.accessibilityLabel() == "World clock style"
        }?.titleOfSelectedItem, "Analog")
      XCTAssertFalse(controller.window?.isVisible ?? true)
      controller.close(); XCTAssertEqual(applications, 0)
    }
  }
}
