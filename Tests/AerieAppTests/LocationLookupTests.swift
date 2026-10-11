import AerieCore
import AppKit
import XCTest
@testable import AerieApp

final class LocationLookupTests: XCTestCase {
  private final class Provider: LocationLookupProvider {
    var callback: ((Result<[LocationChoice], LocationLookupError>) -> Void)?
    var queries: [String] = []; var foreground: Bool?; var cancelled = 0
    func macLocation(
      foreground: Bool,
      completion: @escaping (Result<[LocationChoice], LocationLookupError>) -> Void
    ) {
      self.foreground = foreground; callback = completion
    }
    func search(
      _ query: String, completion: @escaping (Result<[LocationChoice], LocationLookupError>) -> Void
    ) { queries.append(query); callback = completion }
    func cancel() { cancelled += 1 }
  }
  func testNoProviderAtInitializationAndCancellationRejectsLateAndReplacedResults() {
    let first = Provider(), second = Provider(); var made = 0, delivered = 0
    let session = LocationLookupSession {
      made += 1; return made == 1 ? first : second
    }
    XCTAssertEqual(made, 0)
    session.search("Synthetic city") { _ in delivered += 1 }
    let stale = first.callback
    session.macLocation(foreground: false) { _ in delivered += 1 }
    stale?(.failure(.unavailable)); XCTAssertEqual(delivered, 0); XCTAssertEqual(first.cancelled, 1)
    session.cancel(); second.callback?(.failure(.permissionDenied))
    XCTAssertEqual(delivered, 0); XCTAssertEqual(second.cancelled, 1)
  }
  func testSyntheticPointStagesWeatherAndDaylightWithoutEnablingOrApplyingSources() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = PreferencesController(settings: Settings()); defer { controller.close() }
      var applied: Settings?; controller.onApply = { applied = $0 }
      controller.stageLocation(
        LocationChoice(name: "Synthetic public point", latitude: 10, longitude: 20, zone: "Etc/UTC")
      )
      XCTAssertNil(applied)
      let controls = try preferenceControls(controller)
      let apply = try XCTUnwrap(
        controls.compactMap { $0 as? NSButton }.first { $0.title == "Apply" })
      apply.performClick(nil)
      let settings = try XCTUnwrap(applied)
      XCTAssertEqual(settings.weather.latitude, 10); XCTAssertEqual(settings.weather.longitude, 20)
      XCTAssertFalse(settings.weather.enabled); XCTAssertFalse(settings.weather.mapsEnabled);
      XCTAssertNil(settings.daylight)
      let enabled = try XCTUnwrap(
        controls.compactMap { $0 as? NSButton }.first {
          $0.title == "Show offline sunrise, sunset and twilight estimates"
        })
      enabled.state = .on; apply.performClick(nil)
      XCTAssertEqual(applied?.daylight?.latitude, 10);
      XCTAssertEqual(applied?.daylight?.longitude, 20)
      XCTAssertEqual(applied?.daylight?.zone, "Etc/UTC");
      XCTAssertFalse(controller.window?.isVisible ?? true)
    }
  }
  func testSidebarHasNineSectionsAndNoSeparateChangesOrDaylightPage() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = PreferencesController(settings: Settings()); defer { controller.close() }
      let tabs = try preferenceTabs(controller)
      XCTAssertEqual(tabs.tabViewItems.map(\.label), SettingsSection.allCases.map(\.rawValue))
      XCTAssertEqual(tabs.numberOfTabViewItems, 9)
      controller.selectSection(.notifications)
      XCTAssertEqual(tabs.selectedTabViewItem?.label, "Notifications")
      XCTAssertTrue(controller.window?.styleMask.contains(.resizable) ?? false)
    }
  }
  func testSessionDeliversOnceAndSettingsCloseCancelsPendingLookup() async {
    await MainActor.run {
      let provider = Provider(); var delivered = 0
      let session = LocationLookupSession { provider }
      session.search("Synthetic city") { _ in delivered += 1 }
      let callback = provider.callback
      callback?(.failure(.permissionDenied)); callback?(.failure(.unavailable))
      XCTAssertEqual(delivered, 1)
      _ = NSApplication.shared
      let controller = PreferencesController(settings: Settings())
      controller.locationSession = LocationLookupSession { provider }
      controller.locationSession.search("Synthetic city") { _ in delivered += 1 }
      controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification))
      provider.callback?(.failure(.timeout)); XCTAssertEqual(delivered, 1)
      controller.locationSession.search("Synthetic city") { _ in delivered += 1 }
      controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
      provider.callback?(.failure(.timeout)); XCTAssertEqual(delivered, 1)
      XCTAssertGreaterThanOrEqual(provider.cancelled, 2)
    }
  }
  func testLocationChoiceRejectsUnboundedInvalidAndControlCharacterPoints() {
    for point in [
      LocationChoice(name: "", latitude: 10, longitude: 20, zone: "Etc/UTC"),
      LocationChoice(name: "Synthetic\npoint", latitude: 10, longitude: 20, zone: "Etc/UTC"),
      LocationChoice(name: "Synthetic", latitude: .nan, longitude: 20, zone: "Etc/UTC"),
      LocationChoice(name: "Synthetic", latitude: 91, longitude: 20, zone: "Etc/UTC"),
      LocationChoice(name: "Synthetic", latitude: 10, longitude: 181, zone: "Etc/UTC"),
      LocationChoice(name: "Synthetic", latitude: 10, longitude: 20, zone: "Missing/Zone"),
    ] { XCTAssertFalse(point.valid) }
  }

  func testManualLocationEditCancelsLookupAndLateResultCannotReplaceTheDraft() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var settings = Settings(); settings.weather.name = "Original public fixture";
      settings.weather.latitude = 10; settings.weather.longitude = 20
      let controller = PreferencesController(settings: settings); defer { controller.close() }
      let provider = Provider(); controller.locationSession = LocationLookupSession { provider }
      let controls = try preferenceControls(controller)
      let find = try XCTUnwrap(
        controls.compactMap { $0 as? NSButton }.first { $0.title == "Find Location" })
      find.performClick(nil); XCTAssertTrue(controller.locationSession.isPending)
      let latitude = try XCTUnwrap(
        controls.compactMap { $0 as? NSTextField }.first {
          $0.accessibilityLabel() == "Latitude (−90…90)"
        })
      latitude.stringValue = "11"
      controller.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: latitude))
      XCTAssertFalse(controller.locationSession.isPending); XCTAssertEqual(provider.cancelled, 1)
      provider.callback?(
        .success([
          LocationChoice(name: "Late public fixture", latitude: 44, longitude: 55, zone: "Etc/UTC")
        ]))
      XCTAssertEqual(latitude.stringValue, "11")
      var applied: Settings?; controller.onApply = { applied = $0 }
      try XCTUnwrap(controls.compactMap { $0 as? NSButton }.first { $0.title == "Apply" })
        .performClick(nil)
      XCTAssertEqual(applied?.weather.latitude, 11);
      XCTAssertEqual(applied?.weather.name, "Original public fixture")
      XCTAssertFalse(applied?.weather.enabled ?? true);
      XCTAssertFalse(applied?.weather.mapsEnabled ?? true)
    }
  }
  func testApplyCancelsPendingLookupBeforeSavingAndRejectsItsLateResult() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      var settings = Settings(); settings.weather.name = "Original public fixture";
      settings.weather.latitude = 10; settings.weather.longitude = 20
      let controller = PreferencesController(settings: settings); defer { controller.close() }
      let provider = Provider(); controller.locationSession = LocationLookupSession { provider }
      let controls = try preferenceControls(controller)
      try XCTUnwrap(controls.compactMap { $0 as? NSButton }.first { $0.title == "Find Location" })
        .performClick(nil)
      var applied: Settings?; controller.onApply = { applied = $0 }
      try XCTUnwrap(controls.compactMap { $0 as? NSButton }.first { $0.title == "Apply" })
        .performClick(nil)
      XCTAssertFalse(controller.locationSession.isPending); XCTAssertEqual(provider.cancelled, 1)
      provider.callback?(
        .success([
          LocationChoice(name: "Late public fixture", latitude: 44, longitude: 55, zone: "Etc/UTC")
        ]))
      XCTAssertEqual(applied?.weather.latitude, 10)
      let latitude = try XCTUnwrap(
        controls.compactMap { $0 as? NSTextField }.first {
          $0.accessibilityLabel() == "Latitude (−90…90)"
        })
      XCTAssertEqual(Double(latitude.stringValue), 10)
    }
  }
  func testUnknownGeocoderZoneStagesWeatherAndRequiresAnExplicitDaylightZone() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = PreferencesController(settings: Settings()); defer { controller.close() }
      let point = LocationChoice(
        name: "Synthetic remote city", latitude: 10, longitude: 20, zone: nil)
      XCTAssertTrue(point.valid); controller.stageLocation(point)
      let controls = try preferenceControls(controller)
      let zone = try XCTUnwrap(
        controls.compactMap { $0 as? NSTextField }.first {
          $0.accessibilityLabel() == "Daylight time zone"
        })
      XCTAssertTrue(zone.stringValue.isEmpty)
      XCTAssertTrue(
        controls.compactMap { $0 as? NSTextField }.contains {
          $0.stringValue.contains("Daylight time zone unavailable")
        })
      let apply = try XCTUnwrap(
        controls.compactMap { $0 as? NSButton }.first { $0.title == "Apply" })
      var applied: Settings?; controller.onApply = { applied = $0 }; apply.performClick(nil)
      XCTAssertEqual(applied?.weather.latitude, 10); XCTAssertNil(applied?.daylight)
      try XCTUnwrap(
        controls.compactMap { $0 as? NSButton }.first {
          $0.title == "Show offline sunrise, sunset and twilight estimates"
        }
      ).state = .on
      applied = nil; apply.performClick(nil); XCTAssertNil(applied)
      XCTAssertTrue(
        controls.compactMap { $0 as? NSTextField }.contains {
          $0.accessibilityLabel() == "Settings error"
            && $0.stringValue.contains("Choose a daylight time zone")
        })
      zone.stringValue = "Etc/UTC"; apply.performClick(nil)
      XCTAssertEqual(applied?.daylight?.zone, "Etc/UTC");
      XCTAssertEqual(applied?.daylight?.latitude, 10)
      XCTAssertFalse(applied?.weather.enabled ?? true);
      XCTAssertFalse(applied?.weather.mapsEnabled ?? true)
    }
  }
  func testUnrelatedFormatEditKeepsPendingLookupAndOptOutPreservesDaylightPoint() async throws {
    try await MainActor.run {
      _ = NSApplication.shared
      let controller = PreferencesController(settings: Settings()); defer { controller.close() }
      let provider = Provider(); controller.locationSession = LocationLookupSession { provider }
      let controls = try preferenceControls(controller)
      try XCTUnwrap(controls.compactMap { $0 as? NSButton }.first { $0.title == "Find Location" })
        .performClick(nil)
      let format = try XCTUnwrap(
        controls.compactMap { $0 as? NSTextField }.first {
          $0.accessibilityLabel() == "Date format"
        })
      controller.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: format))
      XCTAssertTrue(controller.locationSession.isPending)
      try XCTUnwrap(
        controls.compactMap { $0 as? NSButton }.first {
          $0.title == "Use the chosen location for offline daylight too"
        }
      ).state = .off
      let zone = try XCTUnwrap(
        controls.compactMap { $0 as? NSTextField }.first {
          $0.accessibilityLabel() == "Daylight time zone"
        })
      zone.stringValue = "Etc/UTC"
      provider.callback?(
        .success([
          LocationChoice(name: "Synthetic remote city", latitude: 10, longitude: 20, zone: nil)
        ]))
      XCTAssertEqual(zone.stringValue, "Etc/UTC");
      XCTAssertFalse(controller.locationSession.isPending)
    }
  }

}
