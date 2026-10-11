import Foundation
import XCTest
@testable import AerieCore

final class RedesignPresentationTests: XCTestCase {
  func testFreshClockFollowsSystemAndUnconfiguredWeatherIsHiddenButConfiguredIsStable() throws {
    var settings = Settings()
    XCTAssertTrue(settings.clockFormat.isEmpty)
    XCTAssertFalse(settings.visibleMenus.contains { $0.module == .weather })
    settings.weather.name = "Synthetic point"; settings.weather.latitude = 10;
    settings.weather.longitude = 20
    XCTAssertTrue(settings.visibleMenus.contains { $0.module == .weather })
    XCTAssertFalse(settings.weather.enabled)
    settings.weather.name = ""; settings.combinedModules = [.weather]
    XCTAssertEqual(settings.visibleCombinedModules, [.overview])
    settings.clockFormat = "HH:mm"
    let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    XCTAssertEqual(decoded.clockFormat, "HH:mm")
  }
  func testPlatformScopedCatalogResolvesCollisionsKindCaseUnknownAndNamespaces() {
    XCTAssertEqual(SensorCatalog.name(key: "Tp0P", unit: "°C", platform: .intel), "Powerboard")
    XCTAssertEqual(
      SensorCatalog.name(key: "Tp0P", unit: "°C", platform: .m1), "CPU performance sensor 6")
    XCTAssertEqual(
      SensorCatalog.name(key: "Tp09", unit: "°C", platform: .m1), "CPU efficiency sensor 1")
    XCTAssertEqual(
      SensorCatalog.name(key: "Tp09", unit: "°C", platform: .m2), "CPU performance sensor 3")
    XCTAssertNil(SensorCatalog.name(key: "tp09", unit: "°C", platform: .m1))
    XCTAssertNil(SensorCatalog.name(key: "Tp09", unit: "W", platform: .m1))
    XCTAssertNil(SensorCatalog.name(key: "Tp09", unit: "°C", platform: .unknown))
    XCTAssertNil(SensorCatalog.name(key: "Tp09", unit: "°C", platform: .m1, namespace: "hid"))
    XCTAssertNil(SensorCatalog.name(key: "Z999", unit: "°C", platform: .m4Max))
    XCTAssertEqual(
      SensorPlatform.detect(cpuBrand: "Translated Intel", nativeGPUModels: ["Apple M4 Max"]), .m4Max
    )
    XCTAssertEqual(SensorPlatform.detect(cpuBrand: "Apple M4"), .m4)
    XCTAssertEqual(SensorPlatform.detect(cpuBrand: "Apple M99"), .unknown)
    XCTAssertEqual(SensorPlatform.detect(cpuBrand: "Apple M4 Ultra"), .unknown)
    XCTAssertEqual(SensorPlatform.detect(cpuBrand: "Apple M6 Ultra"), .unknown)
    XCTAssertEqual(SensorPlatform.detect(cpuBrand: "Translated Intel", nativeARM: true), .unknown)
    XCTAssertEqual(SensorPlatform.detect(cpuBrand: "Intel Core", nativeARM: false), .intel)
  }
  func testNotificationDescriptionsUseReadableUnitsWithoutChangingStoredRules() {
    let rule = ThresholdRule(metric: "download", threshold: 20_000_000, duration: 30)
    XCTAssertEqual(
      NotificationPresentation.summary(rule), "Download speed above 20 MB/s for 30 seconds")
    XCTAssertEqual(rule.threshold, 20_000_000)
    XCTAssertEqual(
      NotificationPresentation.summary(
        ThresholdRule(metric: "battery", threshold: 20, comparison: .below, duration: 0)),
      "Battery charge below 20%")
    XCTAssertEqual(
      NotificationPresentation.summary(ThresholdRule(metric: "thermal", threshold: 2, duration: 0)),
      "Thermal pressure above serious")
  }
  func testLegacyJSONPreservesSeparateLayoutCustomClockAndWeatherOnlyFallback() throws {
    var old = Settings(); old.clockFormat = "HH:mm"; old.compactSpacing = false
    old.menus = [MenuConfiguration(module: .weather, visible: true, style: .text)]
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
    for key in ["groupedMenus", "menuPadding", "menuGap"] { object[key] = nil }
    let decoded = try JSONDecoder().decode(
      Settings.self, from: JSONSerialization.data(withJSONObject: object))
    XCTAssertFalse(decoded.effectiveGroupedMenus); XCTAssertEqual(decoded.clockFormat, "HH:mm")
    XCTAssertEqual(decoded.visibleMenus.map(\.module), [.overview])
    XCTAssertEqual(decoded.effectiveMenuPadding, 4); XCTAssertEqual(decoded.effectiveMenuGap, 6)
    var fresh = Settings(); XCTAssertTrue(fresh.effectiveGroupedMenus)
    fresh.menuPadding = 0; fresh.menuGap = 12
    let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(fresh))
    XCTAssertEqual(restored.effectiveMenuPadding, 0); XCTAssertEqual(restored.effectiveMenuGap, 12)
  }
  func testLocalClockUsesLocaleCalendarAndZoneAndRetainsCustomPattern() throws {
    let instant = Date(timeIntervalSince1970: 1_700_000_000), formatter = DateFormatter()
    let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
    let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
    let calendar = Calendar(identifier: .gregorian)
    LocalClockFormat.configure(
      formatter, pattern: "", locale: Locale(identifier: "en_US"), calendar: calendar, zone: utc)
    let us = formatter.string(from: instant)
    LocalClockFormat.configure(
      formatter, pattern: "", locale: Locale(identifier: "en_GB"), calendar: calendar, zone: utc)
    let gb = formatter.string(from: instant)
    XCTAssertNotEqual(us, gb); XCTAssertTrue(gb.contains("22:13"));
    XCTAssertFalse(us.contains("22:13"))
    LocalClockFormat.configure(
      formatter, pattern: "yyyy-MM-dd HH:mm", locale: Locale(identifier: "en_US_POSIX"),
      calendar: calendar, zone: tokyo)
    XCTAssertEqual(formatter.string(from: instant), "2023-11-15 07:13")
  }
  func testReportedWeatherDaylightRetainsMissingInvalidAndNightWithoutNetwork() throws {
    for (value, expected) in [
      ("0", Optional(false)), ("1", Optional(true)), ("2", nil), ("null", nil),
    ] {
      let data = Data(
        ("{\"current\":{\"temperature_2m\":20,\"weather_code\":0,\"is_day\":" + value + "}}").utf8)
      XCTAssertEqual(try OpenMeteoProvider.decode(data).isDay, expected)
    }
    XCTAssertNil(
      try OpenMeteoProvider.decode(Data("{\"current\":{\"temperature_2m\":20}}".utf8)).isDay)
    var settings = Settings(); settings.weather.name = "Synthetic point";
    settings.weather.latitude = 10; settings.weather.longitude = 20
    settings.weather.enabled = true
    let url = try OpenMeteoProvider.requestURL(settings.weather)
    let fields = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first {
      $0.name == "current"
    }?.value
    XCTAssertTrue(fields?.split(separator: ",").contains("is_day") == true)
  }

  func testNWSIconMetadataIsWhitelistedAndDoesNotInferTextOrCompositeTransitions() throws {
    XCTAssertEqual(
      WeatherIconMetadata.nws("https://api.weather.gov/icons/land/night/rain,20?size=medium")?
        .glyph, .rain)
    XCTAssertEqual(
      WeatherIconMetadata.nws("https://api.weather.gov/icons/land/night/rain,20")?.isDay, false)
    XCTAssertEqual(
      WeatherIconMetadata.nws("https://api.weather.gov/icons/land/day/skc")?.glyph, .clear)
    XCTAssertEqual(
      WeatherIconMetadata.nws("https://api.weather.gov/icons/land/day/rain,20/rain_showers,30")?
        .glyph, .rain)
    for url in [
      "https://other.invalid/icons/land/day/rain", "http://api.weather.gov/icons/land/day/rain",
      "https://api.weather.gov/icons/land/day/not_known",
      "https://api.weather.gov/icons/land/day/skc/rain",
      "https://api.weather.gov/icons/marine/day/rain",
      "https://api.weather.gov/icons/land/dawn/rain",
      "https://user@api.weather.gov/icons/land/day/rain",
      "https://api.weather.gov:443/icons/land/day/rain",
    ] {
      XCTAssertNil(WeatherIconMetadata.nws(url))
    }
    let observation = try NWSWeather.observation(
      Data(
        "{\"properties\":{\"timestamp\":\"2024-01-01T00:00:00Z\",\"textDescription\":\"Rain\",\"icon\":\"https://api.weather.gov/icons/land/night/rain\"}}"
          .utf8))
    XCTAssertEqual(observation.icon?.glyph, .rain); XCTAssertEqual(observation.icon?.isDay, false)
    let absent = try NWSWeather.observation(
      Data(
        "{\"properties\":{\"timestamp\":\"2024-01-01T00:00:00Z\",\"textDescription\":\"Rain\"}}"
          .utf8))
    XCTAssertNil(absent.icon)
  }

}
