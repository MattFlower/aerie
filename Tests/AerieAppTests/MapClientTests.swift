import AerieCore
import AppKit
import Foundation
import ImageIO
import XCTest
@testable import AerieApp

private final class SyntheticMapProtocol: URLProtocol {
  static var started: XCTestExpectation?
  static var stopped: XCTestExpectation?
  static var payload: Data?
  static var status = 200
  static var chunks: [Data]?
  static var headers: [String: String]?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.started?.fulfill()
    if let data = Self.payload, let url = request.url,
      let response = HTTPURLResponse(
        url: url, statusCode: Self.status, httpVersion: nil, headerFields: Self.headers)
    {
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      for chunk in Self.chunks ?? [data] { client?.urlProtocol(self, didLoad: chunk) }
      client?.urlProtocolDidFinishLoading(self)
    }
  }
  override func stopLoading() { Self.stopped?.fulfill() }
}
final class MapClientTests: XCTestCase {
  @MainActor func testLegendDrawsBothEndsOfSyntheticHorizontalRampWithoutWindow() throws {
    var pixels = [UInt8](repeating: 0, count: 500 * 30 * 4)
    for y in 0..<30 {
      for x in 0..<500 {
        let offset = (y * 500 + x) * 4
        pixels[offset + (x < 250 ? 0 : 2)] = 255; pixels[offset + 3] = 255
      }
    }
    let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
    let raster = try XCTUnwrap(
      CGImage(
        width: 500, height: 30, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 2000,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let image = NSImage(cgImage: raster, size: NSSize(width: 500, height: 30))
    let view = MapLegendView(frame: NSRect(x: 0, y: 0, width: 512, height: 40))
    view.horizontal = true; view.image = image
    let output = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 40, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0))
    NSGraphicsContext.saveGraphicsState(); defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
    view.draw(view.bounds)
    let left = try XCTUnwrap(output.colorAt(x: 10, y: 20)?.usingColorSpace(.deviceRGB))
    let right = try XCTUnwrap(output.colorAt(x: 500, y: 20)?.usingColorSpace(.deviceRGB))
    XCTAssertGreaterThan(left.redComponent, 0.9); XCTAssertLessThan(left.blueComponent, 0.1)
    XCTAssertGreaterThan(right.blueComponent, 0.9); XCTAssertLessThan(right.redComponent, 0.1)
    XCTAssertNil(view.window)
  }
  @MainActor func testLegendPlacementRetainsWholeHorizontalRampAndVerticalTop() {
    let view = MapLegendView(frame: NSRect(x: 0, y: 0, width: 512, height: 40))
    view.horizontal = true; view.image = NSImage(size: NSSize(width: 500, height: 30))
    XCTAssertEqual(view.imageRect, NSRect(x: 6, y: 0, width: 500, height: 30))
    view.image = NSImage(size: NSSize(width: 1024, height: 80))
    XCTAssertEqual(view.imageRect, NSRect(x: 0, y: 0, width: 512, height: 40))
    view.horizontal = false; view.image = NSImage(size: NSSize(width: 20, height: 800))
    view.setFrameSize(NSSize(width: 145, height: 800))
    XCTAssertEqual(view.imageRect, NSRect(x: 0, y: 0, width: 20, height: 800))
    view.image = nil; XCTAssertEqual(view.imageRect, .zero)
  }
  func testAccessoryRasterRejectsBlankPNGWhileEmptyDataLayersRemainValid() throws {
    func png(_ pixels: [UInt8]) throws -> Data {
      let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
      let image = try XCTUnwrap(
        CGImage(
          width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
      let data = NSMutableData()
      let destination = try XCTUnwrap(
        CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
      CGImageDestinationAddImage(destination, image, nil)
      XCTAssertTrue(CGImageDestinationFinalize(destination))
      return data as Data
    }
    for pixels: [UInt8] in [[0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 255, 0, 0, 0, 255]] {
      let blank = try png(pixels)
      XCTAssertNoThrow(try MapRaster.decode(blank))
      XCTAssertThrowsError(try MapRaster.decode(blank, requireVisibleContent: true))
    }
    let line = try png([0, 0, 0, 0, 255, 0, 0, 255])
    XCTAssertNoThrow(try MapRaster.decode(line, requireVisibleContent: true))
  }
  override func tearDown() {
    SyntheticMapProtocol.started = nil; SyntheticMapProtocol.stopped = nil
    SyntheticMapProtocol.payload = nil; SyntheticMapProtocol.status = 200
    SyntheticMapProtocol.chunks = nil; SyntheticMapProtocol.headers = nil; super.tearDown()
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
  @MainActor func testChunkedBodiesAreBoundedBeforeAccumulationAndDoNotPoisonNextRequest()
    async throws
  {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyntheticMapProtocol.self]
    let client = MapHTTPClient(configuration: configuration); defer { client.close() }
    SyntheticMapProtocol.payload = Data()
    SyntheticMapProtocol.chunks = [
      Data(repeating: 1, count: 1_500_000), Data(repeating: 2, count: 500_001),
    ]
    do {
      _ = try await client.data(WeatherMapKind.radar.endpoint);
      XCTFail("Unknown-length body must stop at the byte limit")
    } catch MapError.oversized {} catch { XCTFail("Unexpected failure: \(error)") }
    SyntheticMapProtocol.chunks = [Data("first".utf8), Data("second".utf8)]
    let resumed = try await client.data(WeatherMapKind.radar.endpoint)
    XCTAssertEqual(resumed, Data("firstsecond".utf8))
  }
  @MainActor func testAdvertisedOversizedBodyIsRejectedAndExactLimitIsAccepted() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyntheticMapProtocol.self]
    let client = MapHTTPClient(configuration: configuration); defer { client.close() }
    SyntheticMapProtocol.payload = Data("small body".utf8)
    SyntheticMapProtocol.headers = ["Content-Length": "2000001"]
    do {
      _ = try await client.data(WeatherMapKind.radar.endpoint);
      XCTFail("Oversized header must fail")
    } catch MapError.oversized {} catch { XCTFail("Unexpected failure: \(error)") }
    SyntheticMapProtocol.headers = nil
    SyntheticMapProtocol.payload = Data(repeating: 0, count: MapHTTPClient.maximumResponseBytes)
    let data = try await client.data(WeatherMapKind.radar.endpoint)
    XCTAssertEqual(data.count, MapHTTPClient.maximumResponseBytes)
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
  func testAlertPresentationDistinguishesCurrentPointScopeAndEachMessageDate() throws {
    let data = Data(
      """
      {"type":"FeatureCollection","features":[{"type":"Feature","properties":{"event":"Synthetic watch","sent":"2026-01-01T00:00:00Z","effective":"2026-01-01T01:00:00Z","onset":"2026-01-01T02:00:00Z","expires":"2026-01-01T04:00:00Z","ends":"2026-01-01T03:00:00Z"}}]}
      """.utf8)
    let report = try WeatherAlerts.parse(data, fetched: Date(timeIntervalSince1970: 0))
    let text = AlertPresentation.text(report)
    for label in [
      "CURRENT NWS ALERTS AT THE MAP CENTER", "Fetched:", "Message sent:", "Effective:", "Onset:",
      "Message expires:", "Event ends:", "historical radar or future forecast frame",
    ] { XCTAssertTrue(text.contains(label)) }
    XCTAssertTrue(text.contains("00:00 UTC")); XCTAssertTrue(text.contains("04:00 UTC"))
  }
}
