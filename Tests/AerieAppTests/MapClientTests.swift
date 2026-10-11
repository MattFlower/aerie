import AerieCore
import Foundation
import ImageIO
import XCTest
@testable import AerieApp

private final class SyntheticMapProtocol: URLProtocol {
  static var started: XCTestExpectation?
  static var stopped: XCTestExpectation?
  static var payload: Data?
  static var status = 200
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.started?.fulfill()
    if let data = Self.payload, let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: Self.status, httpVersion: nil, headerFields: nil)
    {
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() { Self.stopped?.fulfill() }
}
final class MapClientTests: XCTestCase {
  override func tearDown() {
    SyntheticMapProtocol.started = nil; SyntheticMapProtocol.stopped = nil
    SyntheticMapProtocol.payload = nil; SyntheticMapProtocol.status = 200; super.tearDown()
  }
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
  @MainActor func testSuspensionCancelsInflightAndPacedRequestsButAllowsSafeReactivation()
    async throws
  {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyntheticMapProtocol.self]
    let started = expectation(description: "Only the initial synthetic request starts")
    started.assertForOverFulfill = true
    let stopped = expectation(description: "Suspension cancels the live request")
    SyntheticMapProtocol.started = started; SyntheticMapProtocol.stopped = stopped
    let client = MapHTTPClient(configuration: configuration); defer { client.close() }
    let first = Task { try await client.data(WeatherMapKind.radar.endpoint) }
    await fulfillment(of: [started], timeout: 2)
    let paced = Task { try await client.data(WeatherMapKind.satellite.endpoint) }
    try await Task.sleep(nanoseconds: 50_000_000)
    client.suspendRequests()
    for task in [first, paced] {
      do {
        _ = try await task.value; XCTFail("Suspended work must not finish or issue a paced request")
      } catch {}
    }
    await fulfillment(of: [stopped], timeout: 2)
    SyntheticMapProtocol.started = nil; SyntheticMapProtocol.stopped = nil
    SyntheticMapProtocol.payload = Data("synthetic response".utf8)
    let resumed = try await client.data(WeatherMapKind.radar.endpoint)
    XCTAssertEqual(resumed, SyntheticMapProtocol.payload)
  }
  @MainActor func testHTTPFailuresAndOversizedBodiesAreRejected() async {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyntheticMapProtocol.self]
    for (status, data) in [
      (503, Data("synthetic unavailable".utf8)), (200, Data(repeating: 0, count: 2_000_001)),
    ] {
      SyntheticMapProtocol.status = status; SyntheticMapProtocol.payload = data
      let client = MapHTTPClient(configuration: configuration)
      do {
        _ = try await client.data(WeatherMapKind.radar.endpoint);
        XCTFail("Invalid response must fail")
      } catch {}
      client.close()
    }
  }
  func testRedirectsCannotEscapeProviderHTTPSAllowlist() {
    let client = MapHTTPClient(); let session = URLSession(configuration: .ephemeral)
    defer { client.close(); session.invalidateAndCancel() }
    let task = session.dataTask(with: WeatherMapKind.radar.endpoint)
    let response = HTTPURLResponse(
      url: WeatherMapKind.radar.endpoint, statusCode: 302, httpVersion: nil, headerFields: nil)!
    for (address, allowed) in [
      ("https://api.weather.gov/alerts?active=true", true),
      ("https://example.com/image", false), ("http://api.weather.gov/alerts", false),
      ("https://synthetic:synthetic@api.weather.gov/alerts", false),
    ] {
      client.urlSession(
        session, task: task, willPerformHTTPRedirection: response,
        newRequest: URLRequest(url: URL(string: address)!)
      ) { request in
        XCTAssertEqual(request != nil, allowed)
      }
    }
  }
  func testRasterDimensionLimitsRejectSmallCompressedWideImage() throws {
    let width = 1025, height = 1
    let data = Data(repeating: 0, count: width * height * 4)
    let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
    let image = try XCTUnwrap(
      CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let encoded = NSMutableData()
    let destination = try XCTUnwrap(
      CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil);
    XCTAssertTrue(CGImageDestinationFinalize(destination))
    XCTAssertThrowsError(try MapRaster.decode(encoded as Data))
  }
}
