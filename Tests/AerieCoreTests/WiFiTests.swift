import AerieCore
import XCTest

final class WiFiTests: XCTestCase {
  func testErrorSentinelsAndNonfiniteRatesNeverBecomeZeroMeasurements() {
    for value in [0.0, -1, Double.nan, Double.infinity] {
      let sample = WiFiReading(
        interface: "en0", powered: true, rate: value, channel: 0, authorization: .authorized)
      XCTAssertNil(sample.signal); XCTAssertNil(sample.noise); XCTAssertNil(sample.rate)
      XCTAssertNil(sample.channel)
      XCTAssertFalse(sample.fields.contains { $0.1 == "0 dBm" || $0.1 == "0.0 Mbps" })
      XCTAssertFalse(sample.identityNote.contains("permission required"))
      XCTAssertTrue(sample.identityNote.contains("unassociated"))
    }
  }
  func testIdentityIsBoundedPermissionGatedAndCannotReappearAfterRevocation() {
    var sample = WiFiReading(
      interface: "en0", powered: true, mode: .station, signal: -61, noise: -93,
      rate: 866.7, channel: 36, band: "5 GHz", width: "80 MHz", ssid: " Synthetic network ",
      bssid: "02:aa:bb:cc:dd:ee", country: "us", authorization: .authorized)
    XCTAssertEqual(sample.ssid, " Synthetic network ")
    XCTAssertEqual(sample.bssid, "02:AA:BB:CC:DD:EE"); XCTAssertEqual(sample.country, "US")
    XCTAssertEqual(sample.rate, 866.7); XCTAssertEqual(sample.signal, -61)
    sample.recheckAuthorization(.denied)
    XCTAssertNil(sample.ssid); XCTAssertNil(sample.bssid); XCTAssertNil(sample.country)
    XCTAssertEqual(sample.signal, -61); XCTAssertTrue(sample.identityNote.contains("denied"))
    sample.recheckAuthorization(.authorized); XCTAssertNil(sample.ssid)
    for access in [
      WiFiAuthorization.notDetermined, .denied, .restricted, .servicesDisabled, .unknown,
    ] {
      let denied = WiFiReading(
        interface: "en0", powered: true, ssid: "Synthetic", bssid: "02:aa:bb:cc:dd:ee",
        country: "us", authorization: access)
      XCTAssertNil(denied.ssid); XCTAssertNil(denied.bssid); XCTAssertNil(denied.country)
    }
  }
  func testMissingAndInvalidIdentityAndRadioOffRemainDistinct() {
    let invalid = WiFiReading(
      interface: String(repeating: "x", count: 65), powered: true,
      ssid: String(repeating: "x", count: 129), bssid: "00:01:02:03:04:gg", country: "USA",
      authorization: .authorized)
    XCTAssertEqual(invalid.interface, "Wi-Fi")
    XCTAssertNil(invalid.ssid); XCTAssertNil(invalid.bssid); XCTAssertNil(invalid.country)
    let control = WiFiReading(
      interface: "en0", powered: true, ssid: "Synthetic\nname", authorization: .authorized)
    XCTAssertNil(control.ssid)
    let off = WiFiReading(
      interface: "en0", powered: false, signal: -60, noise: -95, rate: 400, channel: 6,
      ssid: "Synthetic", authorization: .authorized)
    XCTAssertEqual(off.fields.count, 2); XCTAssertEqual(off.fields[1].1, "Off")
    XCTAssertNil(off.signal); XCTAssertNil(off.rate); XCTAssertNil(off.channel);
    XCTAssertNil(off.ssid)
  }
}
