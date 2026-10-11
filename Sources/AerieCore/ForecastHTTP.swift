import Foundation

public enum ForecastService: String {
  case openMeteo, nws
  public func allows(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
      url.fragment == nil, url.port == nil || url.port == 443,
      url.absoluteString.utf8.count <= 2048
    else { return false }
    let host = self == .openMeteo ? "api.open-meteo.com" : "api.weather.gov"
    guard url.host?.lowercased() == host else { return false }
    if self == .openMeteo { return url.path == "/v1/forecast" }
    return ["/points/", "/gridpoints/", "/stations/", "/alerts/"].contains {
      url.path.hasPrefix($0)
    }
      || url.path == "/alerts"
  }
}
public enum HTTPService {
  case forecast(ForecastService), publicAddress
  public var maximumBytes: Int {
    switch self {
    case .forecast: return 2_000_000;
    case .publicAddress: return 512
    }
  }
  public func allows(_ url: URL) -> Bool {
    switch self {
    case .forecast(let service): return service.allows(url)
    case .publicAddress:
      guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "api64.ipify.org",
        url.user == nil, url.password == nil, url.fragment == nil,
        url.port == nil || url.port == 443, url.path.isEmpty || url.path == "/",
        url.absoluteString.utf8.count <= 128,
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      else { return false }
      return components.queryItems == [URLQueryItem(name: "format", value: "json")]
    }
  }
}
public protocol ForecastTransport: AnyObject {
  func data(_ url: URL) async throws -> Data
  func close()
}
private final class ForecastCancellation {
  private let lock = NSLock()
  private var task: URLSessionTask?
  private var cancelled = false
  func bind(_ value: URLSessionTask) {
    lock.lock(); task = value; let cancelled = cancelled; lock.unlock()
    if cancelled { value.cancel() }
  }
  func cancel() { lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel() }
}
/// Ephemeral provider-specific transport; byte limits apply before chunk accumulation.
public typealias ForecastHTTPClient = BoundedHTTPClient
public final class BoundedHTTPClient: NSObject, ForecastTransport, URLSessionDataDelegate {
  public static let maximumBytes = 2_000_000
  private final class Pending {
    var data = Data()
    let continuation: CheckedContinuation<Data, Error>
    init(_ value: CheckedContinuation<Data, Error>) { continuation = value }
  }
  private let service: HTTPService
  private let lock = NSLock()
  private var pending: [ObjectIdentifier: Pending] = [:]
  private var session: URLSession?
  private var closed = false
  public convenience init(
    service: ForecastService, configuration: URLSessionConfiguration = .ephemeral
  ) {
    self.init(purpose: .forecast(service), configuration: configuration)
  }
  public init(purpose service: HTTPService, configuration: URLSessionConfiguration = .ephemeral) {
    self.service = service; super.init()
    configuration.urlCache = nil; configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil; configuration.httpShouldSetCookies = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = 30
    configuration.httpMaximumConnectionsPerHost = 2
    session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }
  public func data(_ url: URL) async throws -> Data {
    guard service.allows(url) else { throw WeatherError.invalidConfiguration }
    try Task.checkCancellation()
    var request = URLRequest(url: url)
    request.setValue(
      "Aerie/0.1 (+https://github.com/MattFlower/aerie)", forHTTPHeaderField: "User-Agent")
    request.setValue("application/geo+json, application/json", forHTTPHeaderField: "Accept")
    let cancellation = ForecastCancellation()
    let result: Data = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        lock.lock()
        guard !closed, let session else {
          lock.unlock(); continuation.resume(throwing: CancellationError()); return
        }
        let task = session.dataTask(with: request)
        pending[ObjectIdentifier(task)] = Pending(continuation); lock.unlock()
        cancellation.bind(task); task.resume()
      }
    } onCancel: {
      cancellation.cancel()
    }
    try Task.checkCancellation(); return result
  }
  private func finish(_ task: URLSessionTask, _ result: Result<Data, Error>) {
    lock.lock(); let entry = pending.removeValue(forKey: ObjectIdentifier(task)); lock.unlock()
    entry?.continuation.resume(with: result)
  }
  public func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let http = response as? HTTPURLResponse, let url = http.url, service.allows(url) else {
      finish(dataTask, .failure(WeatherError.invalidResponse)); completionHandler(.cancel); return
    }
    guard http.statusCode == 200 else {
      finish(dataTask, .failure(WeatherError.http(http.statusCode))); completionHandler(.cancel);
      return
    }
    guard response.expectedContentLength <= Int64(service.maximumBytes) else {
      finish(dataTask, .failure(WeatherError.payloadTooLarge)); completionHandler(.cancel); return
    }
    completionHandler(.allow)
  }
  public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data)
  {
    lock.lock(); let entry = pending[ObjectIdentifier(dataTask)]
    let oversized = entry.map { data.count > service.maximumBytes - $0.data.count } ?? false
    if !oversized { entry?.data.append(data) }; lock.unlock()
    if oversized { finish(dataTask, .failure(WeatherError.payloadTooLarge)); dataTask.cancel() }
  }
  public func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?
  ) {
    lock.lock(); let entry = pending.removeValue(forKey: ObjectIdentifier(task)); lock.unlock()
    guard let entry else { return }
    if let error {
      entry.continuation.resume(throwing: error)
    } else {
      entry.continuation.resume(returning: entry.data)
    }
  }
  public func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(request.url.map(service.allows) == true ? request : nil)
  }
  public func close() {
    lock.lock(); closed = true; let session = session; self.session = nil
    let entries = Array(pending.values); pending.removeAll(); lock.unlock()
    session?.invalidateAndCancel()
    for entry in entries { entry.continuation.resume(throwing: CancellationError()) }
  }
}
