import Foundation
#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

public struct PublicAddressReading: Equatable {
  private static let numericCharacters = CharacterSet(charactersIn: "0123456789abcdefABCDEF:.")
  public let address: String
  public let family: String
  public let fetched: Date
  /// Validate only a numeric provider reply. It does not establish routability.
  public static func parse(_ data: Data, date: Date) throws -> Self {
    guard data.count <= 512,
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      object.count == 1, let text = object["ip"] as? String,
      !text.isEmpty, text.utf8.count <= 45,
      text.unicodeScalars.allSatisfy({ numericCharacters.contains($0) }),
      date.timeIntervalSince1970.isFinite
    else { throw WeatherError.invalidResponse }
    // Some OS parsers accept scope suffixes or noncanonical leading-zero quads.
    if text.contains(".") {
      let quad = String(text.split(separator: ":", omittingEmptySubsequences: false).last ?? "")
      let pieces = quad.split(separator: ".", omittingEmptySubsequences: false)
      guard pieces.count == 4,
        pieces.allSatisfy({ piece in
          guard let value = Int(piece), (0...255).contains(value) else { return false }
          return String(value) == piece
        })
      else { throw WeatherError.invalidResponse }
    }
    var v4 = in_addr(), v6 = in6_addr()
    var output = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
    if text.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 {
      guard inet_ntop(AF_INET, &v4, &output, socklen_t(output.count)) != nil else {
        throw WeatherError.invalidResponse
      }
      return .init(address: String(cString: output), family: "IPv4", fetched: date)
    }
    if text.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 {
      guard inet_ntop(AF_INET6, &v6, &output, socklen_t(output.count)) != nil else {
        throw WeatherError.invalidResponse
      }
      return .init(address: String(cString: output), family: "IPv6", fetched: date)
    }
    throw WeatherError.invalidResponse
  }
}
public struct PublicAddressProvider {
  public static let url = URL(string: "https://api64.ipify.org/?format=json")!
  private let factory: () -> ForecastTransport
  public init(
    factory: @escaping () -> ForecastTransport = {
      BoundedHTTPClient(purpose: .publicAddress)
    }
  ) { self.factory = factory }
  public func fetch(date: Date = Date()) async throws -> PublicAddressReading {
    let client = factory(); defer { client.close() }
    let data = try await client.data(Self.url)
    try Task.checkCancellation()
    return try PublicAddressReading.parse(data, date: date)
  }
}
