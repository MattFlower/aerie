import Foundation
import XCTest
@testable import AerieCore

private final class SyntheticAddressTransport: ForecastTransport {
  var payload = Data("{\"ip\":\"203.0.113.7\"}".utf8)
  var closes = 0
  var fails = false
  func data(_ url: URL) async throws -> Data {
    XCTAssertEqual(url, PublicAddressProvider.url)
    if fails { throw WeatherError.http(503) }
    return payload
  }
  func close() { closes += 1 }
}
final class PublicAddressTests: XCTestCase {
  func testNumericProviderRepliesCanonicalizeBothFamiliesWithoutLookup() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let v4 = try PublicAddressReading.parse(Data("{\"ip\":\"203.0.113.7\"}".utf8), date: date)
    XCTAssertEqual(v4.address, "203.0.113.7"); XCTAssertEqual(v4.family, "IPv4");
    XCTAssertEqual(v4.fetched, date)
    let v6 = try PublicAddressReading.parse(
      Data("{\"ip\":\"2001:0DB8:0000:0000:0000:0000:0000:1\"}".utf8), date: date)
    XCTAssertEqual(v6.address, "2001:db8::1"); XCTAssertEqual(v6.family, "IPv6")
    // Documentation ranges are synthetic replies, not a routability assertion.
  }
  func testMalformedScopedPortsNamesExtraMetadataAndOversizeAreRejected() {
    for address in [
      "", "localhost", "203.0.113.7:80", "[2001:db8::1]", "fe80::1%en0", " 203.0.113.7",
      "203.0.113.007", "999.1.1.1", "2001:db8::1\n",
    ] {
      let data = try! JSONSerialization.data(withJSONObject: ["ip": address])
      XCTAssertThrowsError(try PublicAddressReading.parse(data, date: Date()), address)
    }
    for text in [
      "{}", "[]", "{\"ip\":5}", "{\"ip\":\"203.0.113.7\",\"location\":\"Synthetic\"}",
      String(repeating: " ", count: 513),
    ] {
      XCTAssertThrowsError(try PublicAddressReading.parse(Data(text.utf8), date: Date()))
    }
  }
  func testProviderClosesTransportOnSuccessFailureAndInvalidReply() async throws {
    let transport = SyntheticAddressTransport()
    let provider = PublicAddressProvider(factory: { transport })
    let result = try await provider.fetch(); XCTAssertEqual(result.address, "203.0.113.7")
    transport.payload = Data("{}".utf8)
    do { _ = try await provider.fetch(); XCTFail("Invalid reply") } catch {}
    transport.fails = true
    do { _ = try await provider.fetch(); XCTFail("HTTP failure") } catch {}
    XCTAssertEqual(transport.closes, 3)
  }
  func testExactAddressPolicyHasNoWeatherHostGeolocationOrQueryEscape() {
    XCTAssertEqual(HTTPService.publicAddress.maximumBytes, 512)
    XCTAssertEqual(HTTPService.forecast(.nws).maximumBytes, 2_000_000)
    XCTAssertTrue(HTTPService.publicAddress.allows(PublicAddressProvider.url))
    for text in [
      "https://api.ipify.org/?format=json", "https://geo.ipify.org/?format=json",
      "https://api64.ipify.org/?format=jsonp", "https://api64.ipify.org/?format=json&callback=x",
      "http://api64.ipify.org/?format=json", "https://user@api64.ipify.org/?format=json",
      "https://api64.ipify.org:444/?format=json", "https://api64.ipify.org/other?format=json",
      "https://api64.ipify.org/?format=json#fragment", "https://api.weather.gov/alerts",
    ] {
      XCTAssertFalse(HTTPService.publicAddress.allows(URL(string: text)!), text)
    }
    XCTAssertFalse(HTTPService.forecast(.nws).allows(PublicAddressProvider.url))
    XCTAssertFalse(HTTPService.forecast(.openMeteo).allows(PublicAddressProvider.url))
  }
  func testOptionalConsentDefaultsOffAndSurvivesOnlyExplicitLocalSettings() throws {
    var settings = Settings(); XCTAssertFalse(settings.effectivePublicAddress)
    let restored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    XCTAssertNil(restored.publicAddress); XCTAssertFalse(restored.effectivePublicAddress)
    settings.publicAddress = true
    XCTAssertTrue(
      try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        .effectivePublicAddress)
  }
}
