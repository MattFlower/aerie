import Foundation

public struct WeatherAlert {
  public var event, headline, area, sender, severity, urgency, certainty: String
  public var status, messageType, description, instructions: String
  public var sent, effective, onset, expires, ends: Date?
  public var source: URL?
}
public struct WeatherAlertReport {
  public var alerts: [WeatherAlert]
  public var fetched: Date
  public var updated: Date?
  public var moreAvailable: Bool
}

public enum WeatherAlerts {
  /// This point is the manually chosen/panned map center, never inferred device or IP location.
  public static func request(latitude: Double, longitude: Double) throws -> URL {
    guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude),
      (-180...180).contains(longitude)
    else { throw MapError.invalidResponse }
    var components = URLComponents(string: "https://api.weather.gov/alerts/active")!
    let point = String(
      format: "%.2f,%.2f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    components.queryItems = [
      URLQueryItem(name: "point", value: point), URLQueryItem(name: "status", value: "actual"),
    ]
    guard let url = components.url else { throw MapError.invalidResponse }; return url
  }
  public static func parse(_ data: Data, fetched: Date) throws -> WeatherAlertReport {
    guard data.count <= 2_000_000 else { throw MapError.oversized }
    let collection = try JSONDecoder().decode(Collection.self, from: data)
    guard collection.type == "FeatureCollection", collection.features.count <= 1000 else {
      throw MapError.invalidMetadata
    }
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let plain = ISO8601DateFormatter()
    func date(_ value: String?) -> Date? {
      value.flatMap { fractional.date(from: $0) ?? plain.date(from: $0) }
    }
    func text(_ value: String?, limit: Int = 32000) -> String {
      guard let value, !value.isEmpty else { return "Unavailable" }
      let clipped = String(value.prefix(limit))
      return value.count > limit
        ? clipped + "\n[Text truncated; consult the official source for the complete message.]"
        : clipped
    }
    let alerts = try collection.features.prefix(100).map { feature -> WeatherAlert in
      guard feature.type == "Feature", let p = feature.properties else {
        throw MapError.invalidMetadata
      }
      let source = (p.id ?? feature.id).flatMap(URL.init(string:)).flatMap {
        WMS.allowed($0) ? $0 : nil
      }
      return WeatherAlert(
        event: text(p.event, limit: 256), headline: text(p.headline, limit: 2000),
        area: text(p.areaDesc, limit: 4000), sender: text(p.senderName, limit: 256),
        severity: text(p.severity, limit: 64), urgency: text(p.urgency, limit: 64),
        certainty: text(p.certainty, limit: 64), status: text(p.status, limit: 64),
        messageType: text(p.messageType, limit: 64), description: text(p.description),
        instructions: text(p.instruction), sent: date(p.sent), effective: date(p.effective),
        onset: date(p.onset), expires: date(p.expires), ends: date(p.ends), source: source)
    }
    return WeatherAlertReport(
      alerts: alerts, fetched: fetched, updated: date(collection.updated),
      moreAvailable: collection.features.count > 100 || collection.pagination?.next != nil)
  }
  private struct Collection: Decodable {
    var type: String
    var features: [Feature]
    var updated: String?
    var pagination: Pagination?
  }
  private struct Pagination: Decodable { var next: String? }
  private struct Feature: Decodable {
    var type: String; var id: String?; var properties: Properties?
  }
  private struct Properties: Decodable {
    var id, event, headline, areaDesc, senderName, severity, urgency, certainty: String?
    var status, messageType, description, instruction: String?
    var sent, effective, onset, expires, ends: String?
  }
}
