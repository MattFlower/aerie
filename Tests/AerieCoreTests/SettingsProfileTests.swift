import Foundation
import XCTest
@testable import AerieCore

final class SettingsProfileTests: XCTestCase {
  private func configured() -> Settings {
    var s = Settings(); s.interval = 5; s.processCount = 12; s.theme = .dark
    s.weather.enabled = true; s.weather.mapsEnabled = true; s.weather.name = "Synthetic location"
    s.weather.latitude = 10; s.weather.longitude = 20; s.publicAddress = true
    var daylight = DaylightConfiguration(); daylight.enabled = true;
    daylight.name = "Synthetic daylight"
    daylight.latitude = 10; daylight.longitude = 20; s.daylight = daylight
    s.eventCalendars = ["Synthetic-calendar"]; s.persistentHistory = true
    s.rules = [ThresholdRule(metric: "cpu", threshold: 80)]
    s.worldClockStyle = .analog; s.sensorNames = ["TC0P": "Synthetic alias"]
    return s
  }
  func testExportRemovesPrivatePointsSelectionsAndTransferableConsent() throws {
    let original = configured()
    let data = try SettingsProfile.exported(original)
    let exported = try JSONDecoder().decode(Settings.self, from: data)
    XCTAssertEqual(exported.weather, WeatherConfiguration()); XCTAssertNil(exported.daylight)
    XCTAssertNil(exported.eventCalendars); XCTAssertNil(exported.publicAddress)
    XCTAssertNil(exported.persistentHistory); XCTAssertEqual(exported.rules, original.rules)
    XCTAssertEqual(exported.sensorNames, original.sensorNames)
    XCTAssertEqual(exported.interval, 5); XCTAssertEqual(exported.worldClockStyle, .analog)
    XCTAssertLessThanOrEqual(data.count, SettingsProfile.maximumBytes)
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Synthetic location"))
    XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Synthetic-calendar"))
    XCTAssertTrue(original.weather.enabled); XCTAssertTrue(original.effectivePersistentHistory)
  }
  func testImportClearsConsentsAndPointsWithoutLosingOrdinaryConfiguration() throws {
    let original = configured(), data = try JSONEncoder().encode(original)
    for preserved in [false, true] {
      let profile = try SettingsProfile.imported(data, preservingHistory: preserved)
      let value = profile.settings
      XCTAssertEqual(profile.kind, .imported); XCTAssertEqual(try value.validated(), value)
      XCTAssertEqual(value.weather, WeatherConfiguration()); XCTAssertNil(value.daylight)
      XCTAssertEqual(value.eventCalendars, []); XCTAssertFalse(value.effectivePublicAddress)
      XCTAssertEqual(value.effectivePersistentHistory, preserved)
      XCTAssertEqual(value.theme, .dark); XCTAssertEqual(value.processCount, 12)
      XCTAssertEqual(value.rules, original.rules);
      XCTAssertEqual(value.sensorNames, original.sensorNames)
      XCTAssertFalse(profile.summary.contains("Synthetic location"))
      XCTAssertTrue(profile.summary.contains("only when you click Apply"))
    }
  }
  func testDefaultsKeepTheExistingArchivePreferenceAndRequireFreshEventSelection() throws {
    for preserved in [false, true] {
      let profile = SettingsProfile.defaults(preservingHistory: preserved)
      XCTAssertEqual(profile.kind, .defaults); XCTAssertEqual(profile.settings.interval, 1)
      XCTAssertEqual(profile.settings.effectiveSensorSampling, .all)
      XCTAssertEqual(profile.settings.effectivePersistentHistory, preserved)
      XCTAssertEqual(profile.settings.eventCalendars, [])
      XCTAssertFalse(profile.settings.weather.enabled);
      XCTAssertFalse(profile.settings.weather.mapsEnabled)
      XCTAssertTrue(profile.settings.rules.isEmpty); XCTAssertNil(profile.settings.daylight)
      XCTAssertEqual(try profile.settings.validated(), profile.settings)
    }
  }
  func testRejectsFutureVersionsMalformedOversizedAndInvalidSettings() throws {
    for data in [
      Data(), Data("{".utf8), Data("{\"schema\":1}".utf8),
      Data(repeating: 32, count: SettingsProfile.maximumBytes + 1),
    ] {
      XCTAssertThrowsError(try SettingsProfile.imported(data, preservingHistory: false)) {
        XCTAssertEqual($0 as? SettingsProfileError, .invalid)
      }
    }
    XCTAssertThrowsError(
      try SettingsProfile.imported(Data("{\"schema\":2}".utf8), preservingHistory: false)
    ) {
      XCTAssertEqual($0 as? SettingsProfileError, .unsupportedVersion(2))
    }
    var invalid = Settings(); invalid.processCount = 21
    XCTAssertThrowsError(
      try SettingsProfile.imported(JSONEncoder().encode(invalid), preservingHistory: false))
    XCTAssertThrowsError(try SettingsProfile.exported(invalid))
  }
  func testLegacyOptionalFieldsUseExistingDefaultsWithoutInferringConsent() throws {
    var s = Settings(); s.weekStartsMonday = false
    var fields = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
    for key in [
      "calendarOptions", "worldClockStyle", "worldClockOrder", "hourlyForecastHours", "changeRules",
      "persistentHistory",
    ] {
      fields.removeValue(forKey: key)
    }
    let profile = try SettingsProfile.imported(
      JSONSerialization.data(withJSONObject: fields), preservingHistory: false)
    XCTAssertEqual(profile.settings.effectiveCalendarOptions.firstWeekday, 1)
    XCTAssertEqual(profile.settings.effectiveHourlyForecastHours, 24)
    XCTAssertNil(profile.settings.worldClockStyle); XCTAssertNil(profile.settings.changeRules)
    XCTAssertEqual(profile.settings.eventCalendars, []);
    XCTAssertFalse(profile.settings.effectivePersistentHistory)
  }
}
