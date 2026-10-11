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
  @MainActor private func field(_ title: String, in controller: PreferencesController) throws
    -> NSTextField
  {
    try XCTUnwrap(
      try controls(controller).compactMap { $0 as? NSTextField }.first {
        $0.accessibilityLabel() == title
      })
  }
  func
    testImportedChangeRulesPreserveIndependentCooldownsDisabledStateIdentityAndOrderThroughApplyAndExport()
    async throws
  {
    try await MainActor.run {
      _ = NSApplication.shared
      var incoming = Settings()
      var disabled = ChangeRule(kind: .charging, cooldown: 10); disabled.enabled = false
      incoming.changeRules = [
        ChangeRule(kind: .timeZone, cooldown: 4320.5), disabled,
        ChangeRule(kind: .connectivity, cooldown: 604800),
        ChangeRule(kind: .thermal, cooldown: 1440.75),
      ]
      let expected = try XCTUnwrap(incoming.changeRules)
      let profile = try SettingsProfile.imported(
        SettingsProfile.exported(incoming), preservingHistory: false)
      let controller = PreferencesController(settings: Settings()); defer { controller.close() }
      var applied: Settings?; controller.onApply = { applied = $0 };
      controller.onProfileReview = { _ in true }
      XCTAssertTrue(controller.reviewAndStage(profile)); XCTAssertNil(applied)
      for rule in expected {
        XCTAssertEqual(
          try field(rule.kind.title + " cooldown seconds (10–604800)", in: controller).stringValue,
          String(rule.cooldown))
      }
      try button("Apply", in: controller).performClick(nil)
      let result = try XCTUnwrap(applied)
      XCTAssertEqual(result.changeRules, expected)
      let transferred = try SettingsProfile.imported(
        SettingsProfile.exported(result), preservingHistory: false)
      XCTAssertEqual(transferred.settings.changeRules, expected)
    }
  }
  func testEditingOneCooldownLeavesOthersIntactAndNewEnabledKindsUseTheirOwnField() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var original = Settings()
      original.changeRules = [
        ChangeRule(kind: .thermal, cooldown: 400), ChangeRule(kind: .connectivity, cooldown: 50),
      ]
      let controller = PreferencesController(settings: original); defer { controller.close() }
      var applied: Settings?; controller.onApply = { applied = $0 }
      try field(ChangeKind.thermal.title + " cooldown seconds (10–604800)", in: controller)
        .stringValue = "777.5"
      try field(ChangeKind.volumes.title + " cooldown seconds (10–604800)", in: controller)
        .stringValue = "25"
      try button(ChangeKind.volumes.title, in: controller).state = .on
      try button("Apply", in: controller).performClick(nil)
      let rules = try XCTUnwrap(applied?.changeRules)
      XCTAssertEqual(rules.map(\.kind), [.thermal, .connectivity, .volumes])
      XCTAssertEqual(rules.prefix(2).map(\.id), original.changeRules?.map(\.id))
      XCTAssertEqual(rules.map(\.cooldown), [777.5, 50, 25])
      applied = nil
      for invalid in ["NaN", "9", "604801"] {
        try field(ChangeKind.volumes.title + " cooldown seconds (10–604800)", in: controller)
          .stringValue = invalid
        try button("Apply", in: controller).performClick(nil); XCTAssertNil(applied)
      }
    }
  }
  func testImportedSpecialClockNamesSurviveStagingApplyAndAnotherProfileRoundTrip() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var incoming = Settings()
      incoming.clocks = [
        WorldClock(name: "Home | office", zone: "Etc/UTC"),
        WorldClock(name: "Line\nbreak", zone: "Asia/Tokyo"),
        WorldClock(name: "  padded ", zone: "Etc/UTC"),
        WorldClock(name: "Quoted \"name\"", zone: "Etc/UTC"),
      ]
      let profile = try SettingsProfile.imported(
        SettingsProfile.exported(incoming), preservingHistory: false)
      let controller = PreferencesController(settings: Settings()); defer { controller.close() }
      controller.onProfileReview = { _ in true }; var applied: Settings?;
      controller.onApply = { applied = $0 }
      XCTAssertTrue(controller.reviewAndStage(profile))
      let editor = try XCTUnwrap(
        try controls(controller).compactMap { $0 as? NSTextView }.first {
          $0.accessibilityLabel() == "World clocks"
        })
      XCTAssertFalse(editor.isAutomaticQuoteSubstitutionEnabled)
      XCTAssertEqual(try WorldClockForm.parse(editor.string), incoming.clocks)
      try button("Apply", in: controller).performClick(nil)
      XCTAssertEqual(applied?.clocks, incoming.clocks)
      let exported = try SettingsProfile.exported(XCTUnwrap(applied))
      XCTAssertEqual(
        try SettingsProfile.imported(exported, preservingHistory: false).settings.clocks,
        incoming.clocks)
      editor.string = "User edited | Etc/UTC\nHome | office | Asia/Tokyo"
      try button("Apply", in: controller).performClick(nil)
      XCTAssertEqual(applied?.clocks.map(\.name), ["User edited", "Home | office"])
      XCTAssertEqual(applied?.clocks.map(\.zone), ["Etc/UTC", "Asia/Tokyo"])
    }
  }

}
