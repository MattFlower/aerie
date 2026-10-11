import Foundation

public enum ReadingValidity: Equatable {
  case fresh
  case unavailable
  case stale(lastSuccess: Date)
  public func live(_ value: Double?) -> Double? { self == .fresh ? value : nil }
  public var description: String {
    switch self {
    case .fresh: return "Live"
    case .unavailable: return "Unavailable"
    case .stale: return "Stale · latest read unavailable"
    }
  }
}
public enum RateDomain { case network, storage }
extension Format {
  public static func rate(
    _ value: Double?, domain: RateDomain = .storage,
    binary: Bool = true, networkBits: Bool = false
  ) -> String {
    guard let value, value.isFinite, value >= 0 else { return "Unavailable" }
    if domain == .network && networkBits {
      return bytes(value * 8, binary: false).replacingOccurrences(of: "B", with: "bit") + "/s"
    }
    return bytes(value, binary: binary) + "/s"
  }
}
