import XCTest
@testable import AerieCore

final class WeatherAlertTests: XCTestCase {
  func testMessageDatesAndInstructionsRemainDistinctAndGeometryIsOptional() throws {
    let data = Data(
      """
      {"type":"FeatureCollection","updated":"2026-01-01T01:00:00Z","features":[{"type":"Feature","geometry":null,"properties":{
        "id":"https://api.weather.gov/alerts/synthetic","event":"Synthetic watch","headline":"Synthetic message",
        "areaDesc":"Synthetic area","senderName":"Synthetic office","severity":"Moderate","urgency":"Future","certainty":"Possible",
        "status":"Actual","messageType":"Update","sent":"2026-01-01T00:00:00-06:00","effective":"2026-01-01T06:10:00Z",
        "onset":"2026-01-01T07:00:00Z","expires":"2026-01-01T09:00:00.000Z","ends":"2026-01-01T08:00:00Z",
        "description":"Synthetic description","instruction":"Synthetic instructions"}}]}
      """.utf8)
    let report = try WeatherAlerts.parse(data, fetched: Date(timeIntervalSince1970: 0))
    let alert = try XCTUnwrap(report.alerts.first)
    XCTAssertEqual(alert.event, "Synthetic watch"); XCTAssertEqual(alert.messageType, "Update")
    XCTAssertEqual(alert.instructions, "Synthetic instructions");
    XCTAssertNotEqual(alert.sent, alert.effective)
    XCTAssertEqual(alert.expires!.timeIntervalSince(alert.sent!), 10800)
    XCTAssertEqual(alert.ends!.timeIntervalSince(alert.onset!), 3600)
    XCTAssertEqual(alert.source?.host, "api.weather.gov"); XCTAssertFalse(report.moreAvailable)
  }
  func testMissingUnknownDatesAndUntrustedSourceDoNotInventValidity() throws {
    let data = Data(
      """
      {"type":"FeatureCollection","features":[{"type":"Feature","properties":{"id":"https://example.com/synthetic","sent":"invalid","expires":null,"event":"Synthetic"}}]}
      """.utf8)
    let alert = try XCTUnwrap(WeatherAlerts.parse(data, fetched: .distantPast).alerts.first)
    XCTAssertNil(alert.sent); XCTAssertNil(alert.expires); XCTAssertNil(alert.source)
    XCTAssertEqual(alert.instructions, "Unavailable")
  }
  func testEmptyActiveCollectionIsValidButMalformedCollectionIsNot() throws {
    let empty = try WeatherAlerts.parse(
      Data("{\"type\":\"FeatureCollection\",\"features\":[]}".utf8), fetched: .distantPast)
    XCTAssertTrue(empty.alerts.isEmpty); XCTAssertFalse(empty.moreAvailable)
    for invalid in [
      "{}", "{\"type\":\"wrong\",\"features\":[]}",
      "{\"type\":\"FeatureCollection\",\"features\":[{\"type\":\"Feature\",\"properties\":null}]}",
    ] {
      XCTAssertThrowsError(try WeatherAlerts.parse(Data(invalid.utf8), fetched: .distantPast))
    }
    XCTAssertThrowsError(
      try WeatherAlerts.parse(Data(repeating: 0, count: 2_000_001), fetched: .distantPast))
  }
  func testBoundedResultsDisclosePaginationAndDoNotSilentlyClaimAllAlerts() throws {
    let feature: [String: Any] = ["type": "Feature", "properties": ["event": "Synthetic"]]
    let collection: [String: Any] = [
      "type": "FeatureCollection", "features": Array(repeating: feature, count: 101),
    ]
    let report = try WeatherAlerts.parse(
      JSONSerialization.data(withJSONObject: collection), fetched: .distantPast)
    XCTAssertEqual(report.alerts.count, 100); XCTAssertTrue(report.moreAvailable)
    let page = Data(
      "{\"type\":\"FeatureCollection\",\"features\":[],\"pagination\":{\"next\":\"https://api.weather.gov/alerts?cursor=synthetic\"}}"
        .utf8)
    XCTAssertTrue(try WeatherAlerts.parse(page, fetched: .distantPast).moreAvailable)
  }
  func testRequestUsesRoundedExplicitMapCenterAndRejectsInvalidCoordinates() throws {
    let url = try WeatherAlerts.request(latitude: 40.1234, longitude: -100.5678)
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
    XCTAssertEqual(query.first { $0.name == "point" }?.value, "40.12,-100.57")
    XCTAssertEqual(query.first { $0.name == "status" }?.value, "actual")
    XCTAssertThrowsError(try WeatherAlerts.request(latitude: .nan, longitude: 0))
    XCTAssertThrowsError(try WeatherAlerts.request(latitude: 91, longitude: 0))
  }
}
