import XCTest
@testable import AerieCore

final class WeatherTimeTests: XCTestCase {
  private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
  func testForecastInstantsKeepLocationTimezoneAcrossDaylightSavingTransition() {
    let context = WeatherTimeContext(identifier: "America/New_York", offsetSeconds: -14400)
    XCTAssertEqual(context.instantZone.secondsFromGMT(for: date("2024-11-03T05:30:00Z")), -14400)
    XCTAssertEqual(context.instantZone.secondsFromGMT(for: date("2024-11-03T06:30:00Z")), -18000)
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "HH:mm"; formatter.timeZone = context.instantZone
    XCTAssertEqual(formatter.string(from: date("2024-11-03T05:30:00Z")), "01:30")
    XCTAssertEqual(formatter.string(from: date("2024-11-03T06:30:00Z")), "01:30")
  }
  func testDailyDatesRecoverProviderBoundariesInsteadOfShiftingIntoPreviousDay() {
    let context = WeatherTimeContext(identifier: "America/New_York", offsetSeconds: -14400)
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = context.dailyZone
    let boundary = date("2024-11-04T04:00:00Z")
    XCTAssertEqual(formatter.string(from: boundary), "2024-11-04")
    formatter.timeZone = context.instantZone
    XCTAssertEqual(formatter.string(from: boundary), "2024-11-03")
  }
  func testInvalidAndMissingMetadataHaveExplicitFixedOffsetOrUTCFallback() {
    let fixed = WeatherTimeContext(identifier: "Unknown/Zone", offsetSeconds: 19800)
    XCTAssertNil(fixed.identifier); XCTAssertEqual(fixed.instantZone.secondsFromGMT(), 19800)
    XCTAssertTrue(fixed.description.contains("UTC+05:30"))
    let absent = WeatherTimeContext(
      identifier: String(repeating: "x", count: 129), offsetSeconds: Int.max)
    XCTAssertNil(absent.identifier); XCTAssertNil(absent.offsetSeconds)
    XCTAssertEqual(absent.instantZone.secondsFromGMT(), 0)
    XCTAssertTrue(absent.description.contains("unavailable"))
  }
  func testDecoderRetainsZoneAndNeverShiftsUnixInstants() throws {
    let data = Data(
      """
      {"timezone":"Asia/Tokyo","utc_offset_seconds":32400,
       "current":{"temperature_2m":20},
       "hourly":{"time":[1700000000],"temperature_2m":[19],"weather_code":[0]}}
      """.utf8)
    let report = try OpenMeteoProvider.decode(data)
    XCTAssertEqual(report.timeContext.identifier, "Asia/Tokyo")
    XCTAssertEqual(report.timeContext.offsetSeconds, 32400)
    XCTAssertEqual(report.hours.first?.date.timeIntervalSince1970, 1700000000)
    let legacy = try OpenMeteoProvider.decode(Data("{\"current\":{\"temperature_2m\":20}}".utf8))
    XCTAssertEqual(legacy.timeContext.instantZone.secondsFromGMT(), 0)
    XCTAssertTrue(legacy.timeContext.description.contains("unavailable"))
  }
}
