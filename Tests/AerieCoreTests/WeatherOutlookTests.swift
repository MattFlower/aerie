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
  private func period(
    _ start: String, _ end: String, day: Bool, temperature: Double?,
    statistic: ForecastTemperatureStatistic, trend: String? = nil
  ) -> WeatherPeriod {
    WeatherPeriod(
      name: day ? "Synthetic daytime" : "Synthetic overnight", start: date(start), end: date(end),
      isDay: day,
      temperature: temperature, precipitation: day ? 0 : 40, condition: day ? "Clear" : "Rain",
      detail: day ? "Issued high details" : "Issued low details", wind: "5 mph",
      temperatureStatistic: statistic, temperatureTrend: trend, glyph: day ? .clear : .rain)
  }
  func testVerifiedIssuedHighAndFollowingOvernightLowKeepTheirWindowsAndMissingValues() {
    var value = report()
    value.periods = [
      period(
        "2024-11-03T12:00:00Z", "2024-11-03T23:00:00Z", day: true, temperature: 20.2,
        statistic: .maximum),
      period(
        "2024-11-03T23:00:00Z", "2024-11-04T12:00:00Z", day: false, temperature: nil,
        statistic: .minimum),
    ]
    let rows = WeatherOutlookPresentation.outlooks(value, at: value.fetched)
    XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0].title, "Today")
    XCTAssertEqual(rows[0].high, 20.2); XCTAssertNil(rows[0].low)
    XCTAssertEqual(rows[0].qualification, "Partial")
    XCTAssertEqual(rows[0].basis, .daytimeAndOvernight)
    XCTAssertEqual(rows[0].precipitation, 40)
    let message = WeatherOutlookPresentation.message(rows[0], report: value, temperature: .celsius)
    XCTAssertTrue(message.contains("High: 20°C"));
    XCTAssertTrue(message.contains("Low: Unavailable"))
    XCTAssertTrue(message.contains("following overnight"))
    XCTAssertTrue(message.contains("not midnight-to-midnight"))
    let later = WeatherOutlookPresentation.outlooks(value, at: date("2024-11-04T00:00:00Z"))
    XCTAssertEqual(later[0].periodIndices, [1]); XCTAssertNil(later[0].high)
    XCTAssertEqual(later[0].isDay, false)
    XCTAssertTrue(
      WeatherOutlookPresentation.outlooks(value, at: date("2024-11-04T13:00:00Z")).isEmpty)
  }
  func testHourlyOrUnverifiedPeriodTemperaturesNeverBecomeHighLowAndMissingZoneIsQualified() {
    var value = report()
    value.periods = [
      period(
        "2024-11-03T12:00:00Z", "2024-11-03T23:00:00Z", day: true, temperature: 20,
        statistic: .instant),
      period(
        "2024-11-03T23:00:00Z", "2024-11-04T12:00:00Z", day: false, temperature: 10,
        statistic: .unknown),
    ]
    var row = WeatherOutlookPresentation.outlooks(value, at: value.fetched)[0]
    XCTAssertNil(row.high); XCTAssertNil(row.low);
    XCTAssertEqual(row.qualification, "Period details")
    XCTAssertTrue(
      WeatherOutlookPresentation.message(row, report: value, temperature: .celsius).contains(
        "Forecast-period temperature: 20°C"))
    value.periods[0].temperatureStatistic = .maximum;
    value.periods[1].temperatureStatistic = .minimum
    value.timeContext = WeatherTimeContext(identifier: nil, offsetSeconds: nil)
    row = WeatherOutlookPresentation.outlooks(value, at: value.fetched)[0]
    XCTAssertNil(row.high); XCTAssertNil(row.low); XCTAssertEqual(row.basis, .unclassifiedPeriods)
    XCTAssertTrue(row.title.contains("UTC"))
  }
  func testPreDawnMinimumDoesNotReplaceFollowingNightAndDSTUsesCivilDates() {
    var value = report(); value.fetched = date("2024-11-03T06:30:00Z")
    value.periods = [
      period(
        "2024-11-03T06:00:00Z", "2024-11-03T11:00:00Z", day: false, temperature: 7,
        statistic: .minimum),
      period(
        "2024-11-03T11:00:00Z", "2024-11-03T23:00:00Z", day: true, temperature: 20,
        statistic: .maximum),
      period(
        "2024-11-03T23:00:00Z", "2024-11-04T11:00:00Z", day: false, temperature: 12,
        statistic: .minimum),
    ]
    var rows = WeatherOutlookPresentation.outlooks(value, at: value.fetched)
    XCTAssertEqual(rows.count, 1); XCTAssertEqual(rows[0].title, "Today")
    XCTAssertEqual(rows[0].high, 20); XCTAssertEqual(rows[0].low, 12)
    XCTAssertEqual(rows[0].periodIndices, [0, 1, 2])  // Earlier 7° remains inspectable.
    value.periods.removeLast()
    rows = WeatherOutlookPresentation.outlooks(value, at: value.fetched)
    XCTAssertEqual(rows[0].high, 20); XCTAssertNil(rows[0].low)
  }
  func testNonDiurnalTrendDoesNotSwapProviderStatisticRoles() {
    var value = report()
    value.periods = [
      period(
        "2024-11-03T12:00:00Z", "2024-11-03T23:00:00Z", day: true, temperature: 15,
        statistic: .maximum, trend: "falling"),
      period(
        "2024-11-03T23:00:00Z", "2024-11-04T12:00:00Z", day: false, temperature: 20,
        statistic: .minimum, trend: "rising"),
    ]
    let row = WeatherOutlookPresentation.outlooks(value, at: value.fetched)[0]
    // The two source extrema cover disjoint valid windows.
    XCTAssertEqual(row.high, 15); XCTAssertEqual(row.low, 20)
    let message = WeatherOutlookPresentation.message(row, report: value, temperature: .celsius)
    XCTAssertTrue(message.contains("Temperature trend: falling"));
    XCTAssertTrue(message.contains("Temperature trend: rising"))
  }
  func testDailyDatesUseProviderBoundaryAndDaylightRequiresActualSolarTimes() {
    var value = report(); let day = date("2024-11-04T05:00:00Z")
    value.days = [
      WeatherDay(
        date: day, low: 0, high: 10, code: 0, sunrise: day.addingTimeInterval(25200),
        sunset: day.addingTimeInterval(61200), uv: nil, precipitation: nil)
    ]
    let row = WeatherOutlookPresentation.outlooks(value, at: day)[0]
    XCTAssertEqual(row.title, "Today"); XCTAssertEqual(row.basis, .daily)
    XCTAssertEqual(row.high, 10); XCTAssertEqual(row.low, 0)
    var hour = WeatherHour(
      date: day.addingTimeInterval(21600), temperature: 2, precipitation: nil, code: 0)
    XCTAssertEqual(WeatherOutlookPresentation.daylight(hour, report: value), false)
    hour.date = day.addingTimeInterval(28800)
    XCTAssertEqual(WeatherOutlookPresentation.daylight(hour, report: value), true)
    value.days[0].sunset = nil;
    XCTAssertNil(WeatherOutlookPresentation.daylight(hour, report: value))
    hour.isDay = false;
    XCTAssertEqual(WeatherOutlookPresentation.daylight(hour, report: value), false)
    let message = WeatherOutlookPresentation.message(row, report: value, temperature: .celsius)
    XCTAssertTrue(message.contains("Maximum UV index: Unavailable"));
    XCTAssertTrue(message.contains("Sunset: Unavailable"))
  }
  func testOpenMeteoRetainsIndependentMissingExtremaAndRejectsInvalidDailyTime() throws {
    let data = Data(
      #"{"timezone":"Asia/Tokyo","utc_offset_seconds":32400,"current":{"temperature_2m":20},"daily":{"time":[1715612400,1715698800,1715785200],"temperature_2m_min":[null,7,null],"temperature_2m_max":[24,null,null],"weather_code":[0,2,3]}}"#
        .utf8)
    let value = try OpenMeteoProvider.decode(data)
    XCTAssertEqual(value.days.count, 3)
    let rows = WeatherOutlookPresentation.outlooks(value, at: date("2024-05-13T15:00:00Z"))
    XCTAssertEqual(rows[0].title, "Today"); XCTAssertEqual(rows[0].high, 24);
    XCTAssertNil(rows[0].low)
    XCTAssertEqual(rows[1].low, 7); XCTAssertNil(rows[1].high)
    XCTAssertNil(rows[2].low); XCTAssertNil(rows[2].high)
    XCTAssertTrue(rows.allSatisfy { $0.qualification == "Partial" })
    let inverted = try OpenMeteoProvider.decode(
      Data(
        String(decoding: data, as: UTF8.self).replacingOccurrences(
          of: "[null,7,null]", with: "[30,7,null]"
        ).utf8))
    XCTAssertNil(inverted.days[0].low); XCTAssertNil(inverted.days[0].high)
    XCTAssertThrowsError(
      try OpenMeteoProvider.decode(
        Data(
          String(decoding: data, as: UTF8.self).replacingOccurrences(
            of: "1715612400", with: "1e100"
          ).utf8)))
  }
  func testDecoderResolutionIsExplicitAndPreservesSymbolsAndTrends() throws {
    let payload = Data(
      #"{"properties":{"periods":[{"name":"Synthetic day","startTime":"2024-11-03T06:00:00-05:00","endTime":"2024-11-03T18:00:00-05:00","isDaytime":true,"temperature":20,"temperatureUnit":"C","temperatureTrend":"falling","icon":"https://api.weather.gov/icons/land/day/few"},{"name":"Synthetic night","startTime":"2024-11-03T18:00:00-05:00","endTime":"2024-11-04T06:00:00-05:00","isDaytime":false,"temperature":{"value":50,"unitCode":"wmoUnit:degF"},"temperatureTrend":"rising","icon":"https://api.weather.gov/icons/land/night/few"}]}}"#
        .utf8)
    let periods = try NWSWeather.forecast(payload, limit: 14, resolution: .twelveHourly).periods
    XCTAssertEqual(periods.map(\.temperatureStatistic), [.maximum, .minimum])
    XCTAssertEqual(periods[1].temperature, 10);
    XCTAssertEqual(periods[0].temperatureTrend, "falling")
    XCTAssertEqual(periods[1].isDay, false); XCTAssertEqual(periods[1].glyph, .partlyCloudy)
    XCTAssertTrue(
      try NWSWeather.forecast(payload, limit: 14, resolution: .hourly).periods.allSatisfy {
        $0.temperatureStatistic == .instant
      })
    XCTAssertTrue(
      try NWSWeather.forecast(payload, limit: 14).periods.allSatisfy {
        $0.temperatureStatistic == .unknown
      })
  }
}
