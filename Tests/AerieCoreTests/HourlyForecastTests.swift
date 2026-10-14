import Foundation
import XCTest
@testable import AerieCore

private final class HourlyFixtureTransport: ForecastTransport {
  var requested: [URL] = []
  let period: Data
  init(_ period: Data) { self.period = period }
  func data(_ url: URL) async throws -> Data {
    requested.append(url)
    if url.path.hasPrefix("/points/") {
      return Data(
        #"{"properties":{"forecast":"https://api.weather.gov/gridpoints/TST/1,2/forecast","forecastHourly":"https://api.weather.gov/gridpoints/TST/1,2/forecast/hourly","observationStations":"https://api.weather.gov/gridpoints/TST/1,2/stations","timeZone":"America/New_York"}}"#
          .utf8)
    }
    if url.path.hasSuffix("/forecast") || url.path.hasSuffix("/forecast/hourly") { return period }
    throw WeatherError.http(503)
  }
  func close() {}
}
final class HourlyForecastTests: XCTestCase {
  private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
  func testExpandedHourlyArraysPreserveMissingTemperatureAndValidateUnitsIndependently() throws {
    let data = Data(
      #"{"current":{"temperature_2m":12},"hourly":{"time":[1700000000,1700003600],"temperature_2m":[null,0],"weather_code":[71,0],"precipitation_probability":[0,101],"apparent_temperature":[-3,null],"relative_humidity_2m":[0,101],"dew_point_2m":[-10],"wind_speed_10m":[2.5,-1],"wind_gusts_10m":[4,null],"wind_direction_10m":[0,361],"surface_pressure":[1000,0],"cloud_cover":[0,-1],"precipitation":[0,-1],"uv_index":[0,null],"visibility":[0,-1]}}"#
        .utf8)
    let report = try OpenMeteoProvider.decode(data, fetched: epoch)
    XCTAssertEqual(report.hours.count, 2)
    let first = report.hours[0], next = report.hours[1]
    XCTAssertNil(first.temperature); XCTAssertEqual(next.temperature, 0)
    XCTAssertEqual(first.apparent, -3); XCTAssertEqual(first.dewpoint, -10)
    XCTAssertEqual(first.humidity, 0); XCTAssertNil(next.humidity); XCTAssertNil(next.dewpoint)
    XCTAssertEqual(first.wind, 2.5); XCTAssertEqual(first.gusts, 4); XCTAssertNil(next.wind)
    XCTAssertEqual(first.direction, 0); XCTAssertNil(next.direction)
    XCTAssertEqual(first.pressure, 1000); XCTAssertNil(next.pressure)
    XCTAssertEqual(first.cloud, 0); XCTAssertNil(next.cloud)
    XCTAssertEqual(first.precipitation, 0); XCTAssertNil(next.precipitation)
    XCTAssertEqual(first.amount, 0); XCTAssertNil(next.amount)
    XCTAssertEqual(first.uv, 0); XCTAssertEqual(first.visibility, 0)
    XCTAssertNil(first.end); XCTAssertTrue(first.precedingHourAggregates)
    let fields = Dictionary(
      uniqueKeysWithValues: HourlyForecastPresentation.fields(
        first, zone: TimeZone(secondsFromGMT: 0)!, temperature: .celsius))
    XCTAssertTrue(fields["Precipitation / gust timing"]?.contains("preceding hour") == true)
  }
  func testRequestRetainsConsentProviderAndExplicitMeasurementUnitsWithoutCallingService() throws {
    var configuration = WeatherConfiguration(); configuration.enabled = true
    configuration.name = "Synthetic point"; configuration.latitude = 10;
    configuration.longitude = 20
    let url = try OpenMeteoProvider.requestURL(configuration)
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    XCTAssertEqual(url.host, "api.open-meteo.com")
    XCTAssertEqual(query["temperature_unit"], "celsius");
    XCTAssertEqual(query["wind_speed_unit"], "kmh")
    XCTAssertEqual(query["precipitation_unit"], "mm"); XCTAssertEqual(query["forecast_days"], "7")
    XCTAssertTrue(query["hourly"]?.contains("dew_point_2m") == true)
    configuration.enabled = false;
    XCTAssertThrowsError(try OpenMeteoProvider.requestURL(configuration))
    configuration.enabled = true; configuration.provider = "nws"
    XCTAssertThrowsError(try OpenMeteoProvider.requestURL(configuration))
  }
  func testHourlyArraysPayloadAndDatesAreBoundedBeforeFormatting() throws {
    for (count, timestamp) in [(385, 1_700_000_000.0), (1, 1e100)] {
      let data = try JSONSerialization.data(withJSONObject: [
        "current": ["temperature_2m": 12],
        "hourly": [
          "time": Array(repeating: timestamp, count: count),
          "temperature_2m": Array(repeating: 1, count: count),
          "weather_code": Array(repeating: 0, count: count),
        ],
      ])
      XCTAssertThrowsError(try OpenMeteoProvider.decode(data))
    }
    XCTAssertThrowsError(
      try OpenMeteoProvider.decode(Data(repeating: 32, count: ForecastHTTPClient.maximumBytes + 1)))
  }
  func testNWSHourlyFieldsRetainWindowHumidityDewpointAndPublishedWindForms() async throws {
    let period = Data(
      #"{"properties":{"periods":[{"startTime":"2026-11-01T01:00:00-04:00","endTime":"2026-11-01T01:00:00-05:00","isDaytime":false,"temperature":{"value":32,"unitCode":"wmoUnit:degF"},"relativeHumidity":{"value":0,"unitCode":"wmoUnit:percent"},"dewpoint":{"value":32,"unitCode":"wmoUnit:degF"},"windSpeed":{"value":30,"unitCode":"wmoUnit:mi_h-1"},"windGust":{"value":12,"unitCode":"wmoUnit:m_s-1"},"windDirection":"NE","shortForecast":"Synthetic snow","detailedForecast":"Synthetic text"}]}}"#
        .utf8)
    let transport = HourlyFixtureTransport(period)
    var configuration = WeatherConfiguration(); configuration.enabled = true;
    configuration.provider = "nws"
    configuration.name = "Synthetic point"; configuration.latitude = 10;
    configuration.longitude = 20
    let report = try await NWSProvider().fetch(
      configuration: configuration, transport: transport, fetched: epoch)
    let hour = try XCTUnwrap(report.hours.first)
    XCTAssertEqual(hour.humidity, 0); XCTAssertEqual(hour.dewpoint, 0);
    XCTAssertEqual(hour.temperature, 0)
    XCTAssertEqual(try XCTUnwrap(hour.wind), 48.28032, accuracy: 1e-8)
    XCTAssertEqual(try XCTUnwrap(hour.gusts), 43.2, accuracy: 1e-8)
    XCTAssertEqual(hour.end?.timeIntervalSince(hour.date), 3600)
    XCTAssertEqual(hour.detail, "Synthetic text");
    XCTAssertTrue(hour.windDescription?.contains("NE") == true)
    let count = transport.requested.count
    let message = HourlyForecastPresentation.message(hour, report: report, temperature: .celsius)
    XCTAssertEqual(transport.requested.count, count)
    XCTAssertTrue(message.contains("-04:00")); XCTAssertTrue(message.contains("-05:00"))
    XCTAssertTrue(message.contains("cached forecasts"));
    XCTAssertTrue(message.contains("Precipitation amount: Unavailable"))
    var object = try JSONSerialization.jsonObject(with: period) as! [String: Any]
    var properties = object["properties"] as! [String: Any]
    var periods = properties["periods"] as! [[String: Any]]
    periods[0]["windSpeed"] = "5 to 10 mph"; periods[0]["windGust"] = "15 mph"
    periods[0]["relativeHumidity"] = ["value": 50, "unitCode": "unknown"]
    properties["periods"] = periods; object["properties"] = properties
    let decoded = try XCTUnwrap(
      NWSWeather.forecast(JSONSerialization.data(withJSONObject: object), limit: 1).periods.first)
    XCTAssertTrue(decoded.wind.contains("5 to 10 mph")); XCTAssertNil(decoded.windSpeed)
    XCTAssertEqual(decoded.gustDescription, "15 mph"); XCTAssertNil(decoded.humidity)
  }
  func testHourSelectionIsBoundedOrderedAndDistinguishesExpiredWindowsFromUnavailableTemperature() {
    let old = WeatherHour(
      date: epoch.addingTimeInterval(-7200), temperature: nil, precipitation: nil, code: -1,
      end: epoch.addingTimeInterval(-3600))
    let current = WeatherHour(
      date: epoch.addingTimeInterval(-1800), temperature: nil, precipitation: 0, code: -1,
      end: epoch.addingTimeInterval(1800))
    let future = WeatherHour(
      date: epoch.addingTimeInterval(3600), temperature: 0, precipitation: nil, code: 0)
    XCTAssertEqual(
      HourlyForecastPresentation.indices([future, old, current], at: epoch, limit: 24), [2, 0])
    XCTAssertTrue(HourlyForecastPresentation.indices([current], at: epoch, limit: 23).isEmpty)
    XCTAssertTrue(
      HourlyForecastPresentation.indices(
        Array(repeating: current, count: 385), at: epoch, limit: 24
      ).isEmpty)
    XCTAssertTrue(
      HourlyForecastPresentation.indices(
        [current], at: Date(timeIntervalSince1970: .nan), limit: 24
      ).isEmpty)
    let invalid = WeatherHour(
      date: Date(timeIntervalSince1970: 1e100), temperature: 0, precipitation: nil, code: 0)
    XCTAssertTrue(HourlyForecastPresentation.indices([invalid], at: epoch, limit: 24).isEmpty)
  }
  func testDetailFieldsPreserveValidZeroAndRejectNonfiniteOrInvalidRanges() {
    let hour = WeatherHour(
      date: epoch, temperature: nil, precipitation: 0, code: -1, apparent: .nan, humidity: 0,
      dewpoint: -2, wind: 0, gusts: .infinity, direction: 0, pressure: 0, cloud: 0, amount: 0,
      uv: 0, visibility: 0)
    let fields = Dictionary(
      uniqueKeysWithValues: HourlyForecastPresentation.fields(
        hour, zone: TimeZone(secondsFromGMT: 0)!, temperature: .fahrenheit))
    XCTAssertEqual(fields["Temperature"], "Unavailable");
    XCTAssertEqual(fields["Feels like"], "Unavailable")
    XCTAssertEqual(fields["Dew point"], "28°F"); XCTAssertEqual(fields["Humidity"], "0.0%")
    XCTAssertEqual(fields["Wind"], "0.0 km/h"); XCTAssertEqual(fields["Gusts"], "Unavailable")
    XCTAssertEqual(fields["Surface pressure"], "Unavailable")
    XCTAssertEqual(fields["Precipitation probability"], "0.0%");
    XCTAssertEqual(fields["Precipitation amount"], "0.0 mm")
    var settings = Settings(); settings.hourlyForecastHours = 168
    XCTAssertNoThrow(try settings.validated()); settings.hourlyForecastHours = 1000
    XCTAssertThrowsError(try settings.validated())
  }
}
