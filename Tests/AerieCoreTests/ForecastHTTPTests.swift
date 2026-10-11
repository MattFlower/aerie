import Foundation
import XCTest
@testable import AerieCore

private final class SyntheticForecastProtocol: URLProtocol {
  static var chunks: [Data]? = [Data("synthetic".utf8)]
  static var headers: [String: String]?
  static var status = 200
  static var started: XCTestExpectation?
  static var stopped: XCTestExpectation?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.started?.fulfill()
    guard let chunks = Self.chunks else { return }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: Self.headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    for chunk in chunks { client?.urlProtocol(self, didLoad: chunk) }
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() { Self.stopped?.fulfill() }
}
final class ForecastHTTPTests: XCTestCase {
  private let url = URL(string: "https://api.open-meteo.com/v1/forecast")!
  private func client() -> ForecastHTTPClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyntheticForecastProtocol.self]
    return ForecastHTTPClient(service: .openMeteo, configuration: configuration)
  }
  override func tearDown() {
    SyntheticForecastProtocol.chunks = [Data("synthetic".utf8)];
    SyntheticForecastProtocol.headers = nil
    SyntheticForecastProtocol.status = 200; SyntheticForecastProtocol.started = nil;
    SyntheticForecastProtocol.stopped = nil
    super.tearDown()
  }
  func testUnknownLengthChunksCannotExceedBudgetAndClientRecovers() async throws {
    let client = client(); defer { client.close() }
    SyntheticForecastProtocol.chunks = [
      Data(repeating: 0, count: 1_500_000), Data(repeating: 1, count: 500_001),
    ]
    do {
      _ = try await client.data(url); XCTFail("Over-budget response must fail before append")
    } catch WeatherError.payloadTooLarge {} catch { XCTFail("Unexpected error: \(error)") }
    SyntheticForecastProtocol.chunks = [Data(repeating: 0, count: ForecastHTTPClient.maximumBytes)]
    let response = try await client.data(url)
    XCTAssertEqual(response.count, ForecastHTTPClient.maximumBytes)
  }
  func testOversizedHeadersAndHTTPFailureRemainDistinct() async {
    let client = client(); defer { client.close() }
    SyntheticForecastProtocol.headers = ["Content-Length": "2000001"]
    do { _ = try await client.data(url); XCTFail("Oversized header must fail") } catch WeatherError
      .payloadTooLarge
    {} catch { XCTFail("Unexpected error: \(error)") }
    SyntheticForecastProtocol.headers = nil; SyntheticForecastProtocol.status = 429
    do {
      _ = try await client.data(url); XCTFail("Rate limit must fail without retry")
    } catch WeatherError.http(429) {} catch { XCTFail("Unexpected error: \(error)") }
  }
  func testCloseCancelsLiveWorkAndRejectsNewRequests() async {
    let client = client()
    SyntheticForecastProtocol.chunks = nil
    let started = expectation(description: "Synthetic start"),
      stopped = expectation(description: "Synthetic cancellation")
    SyntheticForecastProtocol.started = started; SyntheticForecastProtocol.stopped = stopped
    let task = Task { try await client.data(url) }
    await fulfillment(of: [started], timeout: 2); task.cancel(); client.close()
    do { _ = try await task.value; XCTFail("Cancelled request must not return data") } catch {}
    await fulfillment(of: [stopped], timeout: 2)
    do { _ = try await client.data(url); XCTFail("Closed session must remain closed") } catch {}
  }
  func testProviderRedirectsCannotEscapeExactHostOrScheme() {
    let client = client(); defer { client.close() }
    let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
    let task = session.dataTask(with: url)
    let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)!
    for (address, allowed) in [
      ("https://api.open-meteo.com/v1/forecast?x=1", true),
      ("https://api.weather.gov/points/0,0", false),
      ("http://api.open-meteo.com/v1/forecast", false),
      ("https://user:secret@api.open-meteo.com/v1/forecast", false),
      ("https://api.open-meteo.com:444/v1/forecast", false),
      ("https://api.open-meteo.com/other", false),
    ] {
      client.urlSession(
        session, task: task, willPerformHTTPRedirection: response,
        newRequest: URLRequest(url: URL(string: address)!)
      ) { XCTAssertEqual($0 != nil, allowed) }
    }
    XCTAssertFalse(ForecastService.nws.allows(url))
    XCTAssertTrue(
      ForecastService.nws.allows(URL(string: "https://api.weather.gov/alerts?active=true")!))
  }
}

extension ForecastHTTPTests {
  func testAddressPurposeEnforcesItsSmallStreamingBudgetAndExactRedirects() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SyntheticForecastProtocol.self]
    let client = BoundedHTTPClient(purpose: .publicAddress, configuration: configuration)
    defer { client.close() }
    SyntheticForecastProtocol.chunks = [
      Data(repeating: 0, count: 400), Data(repeating: 0, count: 113),
    ]
    do {
      _ = try await client.data(PublicAddressProvider.url);
      XCTFail("Small budget must apply during receipt")
    } catch WeatherError.payloadTooLarge {} catch { XCTFail("Unexpected error: \(error)") }
    SyntheticForecastProtocol.chunks = [Data(repeating: 0, count: 512)]
    let data = try await client.data(PublicAddressProvider.url); XCTAssertEqual(data.count, 512)
    SyntheticForecastProtocol.headers = ["Content-Length": "513"]
    do {
      _ = try await client.data(PublicAddressProvider.url); XCTFail("Oversized header")
    } catch WeatherError.payloadTooLarge {} catch { XCTFail("Unexpected error: \(error)") }
    let session = URLSession(configuration: .ephemeral); defer { session.invalidateAndCancel() }
    let task = session.dataTask(with: PublicAddressProvider.url)
    let response = HTTPURLResponse(
      url: PublicAddressProvider.url, statusCode: 302, httpVersion: nil, headerFields: nil)!
    client.urlSession(
      session, task: task, willPerformHTTPRedirection: response,
      newRequest: URLRequest(url: URL(string: "https://geo.ipify.org/?format=json")!)
    ) {
      XCTAssertNil($0)
    }
  }
}
