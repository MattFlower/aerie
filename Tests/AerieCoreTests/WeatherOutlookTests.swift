import XCTest
@testable import AerieCore

final class WeatherOutlookTests: XCTestCase {
  private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
  private func report() -> WeatherReport {
    WeatherReport(
      source: "NWS", attributionURL: "https://example.invalid/",
      fetched: date("2024-11-03T16:00:00Z"),
      timeContext: WeatherTimeContext(identifier: "America/New_York", offsetSeconds: -18000),
      hours: [], days: [], alerts: [])
  }
  func testPeriodGroupingUsesLocationDaysAndKeepsDayNightAndPartialTemperaturesHonest() {
    var value = report()
    value.periods = [
      WeatherPeriod(
        name: "Today", start: date("2024-11-03T12:00:00Z"), end: date("2024-11-03T23:00:00Z"),
        isDay: true, temperature: 20.2, precipitation: 0, condition: "Clear",
        detail: "Issued day details", wind: "5 mph", glyph: .clear),
      WeatherPeriod(
        name: "Tonight", start: date("2024-11-03T23:00:00Z"), end: date("2024-11-04T12:00:00Z"),
        isDay: false, temperature: nil, precipitation: 40, condition: "Rain",
        detail: "Issued night details", wind: "10 mph", glyph: .rain),
    ]
    let rows = WeatherOutlookPresentation.outlooks(value, at: value.fetched)
    XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0].title, "Today")
    XCTAssertEqual(rows[0].day, 20.2); XCTAssertNil(rows[0].night)
    XCTAssertNil(rows[0].low); XCTAssertNil(rows[0].high)
    XCTAssertEqual(rows[0].precipitation, 40)
    let message = WeatherOutlookPresentation.message(rows[0], report: value, temperature: .celsius)
    XCTAssertTrue(message.contains("20.2°C"));
    XCTAssertTrue(message.contains("Issued night details"))
    XCTAssertTrue(message.contains("not calculated daily extrema"))
    let later = WeatherOutlookPresentation.outlooks(value, at: date("2024-11-04T00:00:00Z"))
    XCTAssertEqual(later[0].periodIndices, [1]); XCTAssertNil(later[0].day)
    XCTAssertEqual(later[0].isDay, false)
    XCTAssertTrue(
      WeatherOutlookPresentation.outlooks(value, at: date("2024-11-04T13:00:00Z")).isEmpty)
  }
  func testDailyDatesUseProviderBoundaryAndDaylightRequiresActualSolarTimes() {
    var value = report()
    let day = date("2024-11-04T05:00:00Z")
    value.days = [
      WeatherDay(
        date: day, low: 0, high: 10, code: 0, sunrise: day.addingTimeInterval(25200),
        sunset: day.addingTimeInterval(61200), uv: nil, precipitation: nil)
    ]
    XCTAssertEqual(WeatherOutlookPresentation.outlooks(value, at: day).first?.title, "Today")
    var hour = WeatherHour(
      date: day.addingTimeInterval(21600), temperature: 2, precipitation: nil, code: 0)
    XCTAssertEqual(WeatherOutlookPresentation.daylight(hour, report: value), false)
    hour.date = day.addingTimeInterval(28800)
    XCTAssertEqual(WeatherOutlookPresentation.daylight(hour, report: value), true)
    value.days[0].sunset = nil
    XCTAssertNil(WeatherOutlookPresentation.daylight(hour, report: value))
    hour.isDay = false
    XCTAssertEqual(WeatherOutlookPresentation.daylight(hour, report: value), false)
    let message = WeatherOutlookPresentation.message(
      WeatherOutlookPresentation.outlooks(value, at: day)[0], report: value, temperature: .celsius)
    XCTAssertTrue(message.contains("Maximum UV index: Unavailable"))
    XCTAssertTrue(message.contains("Sunset: Unavailable"))
  }
  func testRecognizedProviderIconAndDaylightSurviveForecastDecoding() throws {
    let payload = Data(
      #"{"properties":{"periods":[{"name":"Synthetic night","startTime":"2024-11-03T23:00:00-05:00","endTime":"2024-11-04T06:00:00-05:00","isDaytime":false,"temperature":10,"temperatureUnit":"C","shortForecast":"Mostly clear","icon":"https://api.weather.gov/icons/land/night/few"}]}}"#
        .utf8)
    let periods = try NWSWeather.forecast(payload, limit: 14).periods
    XCTAssertEqual(periods[0].isDay, false); XCTAssertEqual(periods[0].glyph, .partlyCloudy)
  }
}
