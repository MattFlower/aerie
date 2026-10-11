import Foundation

public enum WiFiAuthorization: Equatable {
  case notDetermined, denied, restricted, authorized, servicesDisabled, unknown
  public var description: String {
    switch self {
    case .notDetermined:
      return "Location access undecided · use Permissions to allow Wi-Fi identity"
    case .denied: return "Location access denied · Wi-Fi identity unavailable"
    case .restricted: return "Location access restricted · Wi-Fi identity unavailable"
    case .authorized:
      return "Location access authorized · availability depends on macOS and app use"
    case .servicesDisabled: return "Location Services disabled · Wi-Fi identity unavailable"
    case .unknown: return "Location authorization unavailable · Wi-Fi identity withheld"
    }
  }
}

public enum WiFiMode: String {
  case station = "Station", peer = "Peer network", accessPoint = "Access point"
  case none = "No active network reported", unknown = "Operating mode unavailable"
}

/// A bounded copy of passive interface properties. CoreWLAN's zero error sentinels stay missing.
public struct WiFiReading {
  public let interface: String
  public let powered: Bool
  public let mode: WiFiMode
  public let signal, noise: Int?
  public let rate: Double?
  public let channel: Int?
  public let band, width: String?
  public let fetched: Date
  public private(set) var authorization: WiFiAuthorization
  public private(set) var ssid, bssid, country: String?

  public init(
    interface: String?, powered: Bool, mode: WiFiMode = .unknown,
    signal: Int = 0, noise: Int = 0, rate: Double = 0, channel: Int? = nil,
    band: String? = nil, width: String? = nil, ssid: String? = nil, bssid: String? = nil,
    country: String? = nil, authorization: WiFiAuthorization, fetched: Date = Date()
  ) {
    self.interface = Self.bounded(interface, bytes: 64) ?? "Wi-Fi"
    self.powered = powered; self.mode = powered ? mode : .none; self.fetched = fetched
    self.signal = powered && signal != 0 ? signal : nil
    self.noise = powered && noise != 0 ? noise : nil
    self.rate = powered && rate.isFinite && rate > 0 ? rate : nil
    self.channel = powered ? channel.flatMap { $0 > 0 ? $0 : nil } : nil
    self.band = powered ? Self.bounded(band, bytes: 32) : nil
    self.width = powered ? Self.bounded(width, bytes: 32) : nil
    self.authorization = authorization
    if powered && authorization == .authorized {
      self.ssid = Self.bounded(ssid, bytes: 128)
      if let bssid, bssid.utf8.count == 17,
        bssid.split(separator: ":", omittingEmptySubsequences: false).count == 6,
        bssid.split(separator: ":").allSatisfy({
          $0.utf8.count == 2
            && $0.utf8.allSatisfy {
              (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
            }
        })
      {
        self.bssid = bssid.uppercased()
      }
      if let country, country.utf8.count == 2,
        country.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) })
      {
        self.country = country.uppercased()
      }
    }
  }
  private static func bounded(_ value: String?, bytes: Int) -> String? {
    guard let value, !value.isEmpty, value.utf8.count <= bytes,
      !value.unicodeScalars.contains(where: { $0.value < 32 || (127...159).contains($0.value) })
    else { return nil }
    return value
  }
  /// Rechecking cannot restore a previously discarded identity from a stale reading.
  public mutating func recheckAuthorization(_ access: WiFiAuthorization) {
    authorization = access
    if access != .authorized { ssid = nil; bssid = nil; country = nil }
  }
  public var fields: [(String, String)] {
    var rows = [("Interface", interface), ("Radio", powered ? "On" : "Off")]
    guard powered else { return rows }
    rows.append(("Operating mode", mode.rawValue))
    rows.append(("SSID", ssid ?? "Unavailable"))
    rows.append(("BSSID", bssid ?? "Unavailable"))
    rows.append(("Country", country ?? "Unavailable"))
    rows.append(("Signal", signal.map { "\($0) dBm" } ?? "Unavailable"))
    rows.append(("Noise", noise.map { "\($0) dBm" } ?? "Unavailable"))
    rows.append(("Link rate", rate.map { String(format: "%.1f Mbps", $0) } ?? "Unavailable"))
    rows.append(("Channel", channel.map(String.init) ?? "Unavailable"))
    rows.append(("Band", band ?? "Unavailable"))
    rows.append(("Channel width", width ?? "Unavailable"))
    return rows
  }
  public var identityNote: String {
    if authorization != .authorized { return authorization.description }
    if powered && ssid == nil {
      return
        "SSID unavailable: the interface may be unassociated, unreadable or unencodable. Authorization alone does not guarantee a reading."
    }
    return authorization.description
  }
}
