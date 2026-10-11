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

}
