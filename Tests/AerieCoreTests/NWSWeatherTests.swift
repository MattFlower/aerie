import Foundation
import XCTest
@testable import AerieCore

private final class SyntheticNWSTransport: ForecastTransport {
  var responses: [String: Data] = [:]
  var requested: [URL] = []
  func data(_ url: URL) async throws -> Data {
    requested.append(url)
    guard let data = responses[url.path] else { throw WeatherError.http(503) }
    return data
  }
  func close() {}
}
final class NWSWeatherTests: XCTestCase {
  private func data(_ value: String) -> Data { Data(value.utf8) }
  private let point =
    #"{"properties":{"forecast":"https://api.weather.gov/gridpoints/TST/1,2/forecast","forecastHourly":"https://api.weather.gov/gridpoints/TST/1,2/forecast/hourly","observationStations":"https://api.weather.gov/gridpoints/TST/1,2/stations","timeZone":"America/New_York"}}"#
  private let periods =
    #"{"properties":{"updated":"2026-03-08T06:00:00Z","periods":[{"name":"Synthetic day","startTime":"2026-03-08T01:00:00-05:00","endTime":"2026-03-08T03:00:00-04:00","isDaytime":true,"temperature":50,"temperatureUnit":"F","shortForecast":"Rain","detailedForecast":"Synthetic forecast text","probabilityOfPrecipitation":{"value":0,"unitCode":"wmoUnit:percent"},"windSpeed":"5 to 10 mph","windDirection":"NE"},{"name":"Synthetic night","startTime":"2026-03-08T03:00:00-04:00","endTime":"2026-03-08T04:00:00-04:00","isDaytime":false,"temperature":null,"temperatureUnit":"F"}]}}"#
  func testExplicitNWSConsentAndDiscoveryCannotSwitchProvider() throws {
    var c = WeatherConfiguration(); c.name = "Synthetic location"; c.latitude = 10.12345;
    c.longitude = 20.98765; c.provider = "nws"
    XCTAssertThrowsError(try NWSWeather.pointURL(c)); c.enabled = true
    XCTAssertEqual(try NWSWeather.pointURL(c).path, "/points/10.12,20.99")
    XCTAssertThrowsError(try OpenMeteoProvider.requestURL(c))
    XCTAssertEqual(try NWSWeather.point(data(point)).timezone, "America/New_York")
    XCTAssertThrowsError(
      try NWSWeather.point(
        data(point.replacingOccurrences(of: "api.weather.gov", with: "example.com"))))
  }
  func testStationDistanceAndIdentifiersKeepOnlyValidClosestCandidates() throws {
    let json =
      #"{"type":"FeatureCollection","features":[{"properties":{"stationIdentifier":"FAR"},"geometry":{"type":"Point","coordinates":[20,80]}},{"properties":{"stationIdentifier":"NEAR","name":"Synthetic station"},"geometry":{"type":"Point","coordinates":[20,10]}},{"properties":{"stationIdentifier":"../../escape"},"geometry":{"type":"Point","coordinates":[20,10]}}]}"#
    let stations = try NWSWeather.stations(data(json), latitude: 10, longitude: 20)
    XCTAssertEqual(stations.map(\.identifier), ["NEAR", "FAR"])
    XCTAssertEqual(stations[0].observationURL.query, "require_qc=true")
  }
  func testObservationsConvertOnlyKnownUnitsAndKeepNullUnknownAndStaleExplicit() throws {
    let json =
      #"{"properties":{"timestamp":"2026-03-08T06:00:00Z","temperature":{"value":50,"unitCode":"wmoUnit:degF"},"windSpeed":{"value":2,"unitCode":"wmoUnit:m_s-1"},"windGust":{"value":null,"unitCode":"wmoUnit:m_s-1"},"barometricPressure":{"value":100000,"unitCode":"wmoUnit:Pa"},"relativeHumidity":{"value":101,"unitCode":"wmoUnit:percent"},"windChill":{"value":8,"unitCode":"unknown"}}}"#
    let observation = try NWSWeather.observation(data(json))
    XCTAssertEqual(observation.temperature, 10); XCTAssertEqual(observation.wind, 7.2)
    XCTAssertEqual(observation.pressure, 1000); XCTAssertNil(observation.humidity)
    XCTAssertNil(observation.apparent); XCTAssertNil(observation.gusts)
    XCTAssertTrue(observation.isFresh(at: observation.date.addingTimeInterval(1200)))
    XCTAssertFalse(observation.isFresh(at: observation.date.addingTimeInterval(5401)))
    XCTAssertFalse(observation.isFresh(at: observation.date.addingTimeInterval(-301)))
  }
  func testPeriodsRetainDSTInstantsAndMissingTemperatureWithoutInventingDailyExtremes() throws {
    let result = try NWSWeather.forecast(data(periods), limit: 14)
    XCTAssertEqual(result.periods.count, 2)
    XCTAssertEqual(result.periods[0].end.timeIntervalSince(result.periods[0].start), 3600)
    XCTAssertEqual(result.periods[0].temperature, 10);
    XCTAssertEqual(result.periods[0].precipitation, 0)
    XCTAssertNil(result.periods[1].temperature)
    XCTAssertEqual(result.periods[0].detail, "Synthetic forecast text")
    let quantitative = periods.replacingOccurrences(
      of: #""temperature":50"#, with: #""temperature":{"value":10,"unitCode":"wmoUnit:degC"}"#)
    XCTAssertEqual(
      try NWSWeather.forecast(data(quantitative), limit: 1).periods.first?.temperature, 10)
  }
  func testCompositeForecastSurvivesMissingStationAndAlertResponsesWithoutFallback() async throws {
    let transport = SyntheticNWSTransport()
    transport.responses["/points/10.00,20.00"] = data(point)
    transport.responses["/gridpoints/TST/1,2/forecast"] = data(periods)
    transport.responses["/gridpoints/TST/1,2/forecast/hourly"] = data(periods)
    var c = WeatherConfiguration(); c.enabled = true; c.provider = "nws";
    c.name = "Synthetic point"; c.latitude = 10; c.longitude = 20
    let report = try await NWSProvider().fetch(
      configuration: c, transport: transport, fetched: Date(timeIntervalSince1970: 0))
    XCTAssertEqual(report.source, "NWS"); XCTAssertEqual(report.hours.count, 2)
    XCTAssertEqual(report.periods.count, 2); XCTAssertTrue(report.days.isEmpty)
    XCTAssertNil(report.temperature); XCTAssertNil(report.observationTime);
    XCTAssertNil(report.alertReport)
    XCTAssertTrue(report.notes.contains { $0.contains("Station observations unavailable") })
    XCTAssertTrue(transport.requested.allSatisfy { $0.host == "api.weather.gov" })
  }
}
