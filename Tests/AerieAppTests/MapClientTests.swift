import AerieCore
import Foundation
import XCTest
@testable import AerieApp

private final class SyntheticMapProtocol: URLProtocol {
  static var started: XCTestExpectation?
  static var stopped: XCTestExpectation?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() { Self.started?.fulfill() }
  override func stopLoading() { Self.stopped?.fulfill() }
}
final class MapClientTests: XCTestCase {
  @MainActor func testCloseCancelsInflightRequestAndRejectsFurtherRequests() async {
    let configuration = URLSessionConfiguration.ephemeral;
    configuration.protocolClasses = [SyntheticMapProtocol.self]
    let started = expectation(description: "Synthetic request started")
    let stopped = expectation(description: "Synthetic request cancelled")
    SyntheticMapProtocol.started = started; SyntheticMapProtocol.stopped = stopped
    let client = MapHTTPClient(configuration: configuration)
    let task = Task { try await client.data(WeatherMapKind.radar.endpoint) }
    await fulfillment(of: [started], timeout: 2)
    task.cancel(); client.close()
    do { _ = try await task.value; XCTFail("Closed requests must not produce a frame") } catch {}
    await fulfillment(of: [stopped], timeout: 2)
    do {
      _ = try await client.data(WeatherMapKind.radar.endpoint);
      XCTFail("Closed client must stay closed")
    } catch {}
    SyntheticMapProtocol.started = nil; SyntheticMapProtocol.stopped = nil
  }
  func testInvalidRasterDoesNotEnterDecodedCache() {
    XCTAssertThrowsError(try MapRaster.decode(Data("synthetic invalid image".utf8)))
  }
}
