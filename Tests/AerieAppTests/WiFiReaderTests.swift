import AerieCore
import Foundation
import XCTest
@testable import AerieApp

private final class SyntheticWiFiSource: WiFiSource {
  var calls = 0, closed = false, unavailable = false
  func read(authorization: WiFiAuthorization) -> WiFiReading? {
    calls += 1
    guard !unavailable else { return nil }
    // Deliberately return an authorized identity; the reader must still filter the current gate.
    return WiFiReading(
      interface: "en0", powered: true, signal: -60, rate: 400, ssid: "Synthetic network",
      bssid: "02:00:00:00:00:01", country: "US", authorization: .authorized)
  }
  func close() { closed = true }
}
final class WiFiReaderTests: XCTestCase {
  func testClosedReaderIsLazyAndCadencePathAuthorizationAndReopenAreExplicit() {
    var allocations = 0
    let source = SyntheticWiFiSource()
    let reader = WiFiReader {
      allocations += 1; source.closed = false; return source
    }
    XCTAssertNil(reader.current(time: 0, path: 1, authorization: .authorized))
    XCTAssertEqual(allocations, 0)
    reader.configure(visible: true)
    XCTAssertNotNil(reader.current(time: 0, path: 1, authorization: .authorized)?.ssid)
    _ = reader.current(time: 29, path: 1, authorization: .authorized)
    XCTAssertEqual(source.calls, 1)
    _ = reader.current(time: 30, path: 1, authorization: .authorized)
    _ = reader.current(time: 31, path: 2, authorization: .authorized)
    XCTAssertEqual(source.calls, 3)
    let revoked = reader.current(time: 32, path: 2, authorization: .denied)
    XCTAssertNil(revoked?.ssid); XCTAssertNil(revoked?.bssid); XCTAssertNil(revoked?.country)
    XCTAssertEqual(revoked?.signal, -60)
    XCTAssertEqual(source.calls, 4)
    reader.configure(visible: false)
    XCTAssertNil(reader.reading); XCTAssertTrue(source.closed)
    XCTAssertNil(reader.current(time: 100, path: 2, authorization: .authorized))
    reader.configure(visible: true)
    XCTAssertNotNil(reader.current(time: 100, path: 2, authorization: .authorized))
    XCTAssertEqual(allocations, 2); XCTAssertEqual(source.calls, 5)
  }
  func testCloseReleasesSourceMissingAndRollbackNeverReuseOldIdentity() {
    weak var retained: SyntheticWiFiSource?
    let reader = WiFiReader {
      let source = SyntheticWiFiSource(); retained = source; return source
    }
    reader.configure(visible: true)
    _ = reader.current(time: 500, path: 1, authorization: .authorized)
    XCTAssertNotNil(retained)
    retained?.unavailable = true
    XCTAssertNil(reader.current(time: 1, path: 1, authorization: .authorized))
    XCTAssertNil(reader.reading)
    XCTAssertNil(reader.current(time: .nan, path: 1, authorization: .authorized))
    reader.configure(visible: false); XCTAssertNil(retained)
  }
  func testEveryOwnerClearsIdentityOnCloseModuleChangePauseAndLateDelivery() {
    var original = Snapshot()
    original.wifi = WiFiReading(
      interface: "en0", powered: true, ssid: "Synthetic", authorization: .authorized)
    for (module, suspended) in [
      (Optional<Module>.none, false), (.storage, false), (.network, true),
    ] {
      var owners = Array(repeating: original, count: 4)
      for index in owners.indices {
        owners[index].releaseActiveViewState(module: module, suspended: suspended)
      }
      XCTAssertTrue(owners.allSatisfy { $0.wifi == nil })
    }
    var visible = original; visible.releaseActiveViewState(module: .network, suspended: false)
    XCTAssertNotNil(visible.wifi?.ssid)
    visible.wifi?.recheckAuthorization(.restricted); XCTAssertNil(visible.wifi?.ssid)
  }
}
