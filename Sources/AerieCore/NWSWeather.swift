import Foundation
import CoreFoundation

public struct WeatherPeriod: Equatable {
  public let name: String
  public let start, end: Date
  public let isDay: Bool
  public let temperature, precipitation: Double?
  public let condition, detail, wind: String
  public var glyph: WeatherGlyph? = nil
  public var humidity: Double? = nil
  public var dewpoint: Double? = nil
  public var windSpeed: Double? = nil
  public var gusts: Double? = nil
  public var gustDescription: String? = nil
}
public struct NWSPoint {
  public let forecast, hourly, stations: URL
  public let timezone: String?
}
public struct NWSStation {
  public let identifier, name: String
  public let latitude, longitude: Double
  public var observationURL: URL {
    var url = URLComponents(
      string: "https://api.weather.gov/stations/\(identifier)/observations/latest")!
    url.queryItems = [URLQueryItem(name: "require_qc", value: "true")]
    return url.url!
  }
}
public struct NWSObservation {
  public let date: Date
  public let temperature, apparent, humidity, wind, gusts, direction, pressure: Double?
  public let condition: String?
  public var icon: WeatherIconMetadata? = nil
  public func isFresh(at now: Date) -> Bool {
    (-300...5400).contains(now.timeIntervalSince(date))
  }
}
public enum NWSWeather {
  private static let dateLock = NSLock()
  private static let plainDate = ISO8601DateFormatter()
  private static let fractionalDate: ISO8601DateFormatter = {
    let value = ISO8601DateFormatter();
    value.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return value
  }()
  private static func object(_ data: Data) throws -> [String: Any] {
    guard data.count <= ForecastHTTPClient.maximumBytes else { throw WeatherError.payloadTooLarge }
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw WeatherError.invalidResponse
    }
    return value
  }
  private static func properties(_ data: Data) throws -> [String: Any] {
    guard let value = try object(data)["properties"] as? [String: Any] else {
      throw WeatherError.invalidResponse
    }
    return value
  }
  static func date(_ string: String?) -> Date? {
    guard let string, string.utf8.count <= 64 else { return nil }
    dateLock.lock(); defer { dateLock.unlock() }
    return fractionalDate.date(from: string) ?? plainDate.date(from: string)
  }
  private static func text(_ value: Any?, limit: Int) -> String {
    String((value as? String ?? "").prefix(limit))
  }
  private static func number(_ value: Any?) -> Double? {
    guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
      value.doubleValue.isFinite
    else { return nil }
    return value.doubleValue
  }
  private static func quantity(_ value: Any?, kind: String) -> Double? {
    guard let q = value as? [String: Any], let value = number(q["value"]),
      let unit = q["unitCode"] as? String
    else { return nil }
    func wind(_ factor: Double) -> Double? {
      let converted = value * factor
      return value >= 0 && converted.isFinite ? converted : nil
    }
    switch (kind, unit) {
    case ("temperature", "wmoUnit:degC"): return value
    case ("temperature", "wmoUnit:degF"): return (value - 32) / 1.8
    case ("temperature", "wmoUnit:K"): return value - 273.15
    case ("wind", "wmoUnit:km_h-1"): return value >= 0 ? value : nil
    case ("wind", "wmoUnit:m_s-1"): return wind(3.6)
    case ("wind", "wmoUnit:mi_h-1"): return wind(1.609344)
    case ("wind", "wmoUnit:kt"): return wind(1.852)
    case ("percent", "wmoUnit:percent"): return (0...100).contains(value) ? value : nil
    case ("direction", "wmoUnit:degree_(angle)"): return (0...360).contains(value) ? value : nil
    case ("pressure", "wmoUnit:Pa"): return value > 0 ? value / 100 : nil
    case ("pressure", "wmoUnit:hPa"): return value > 0 ? value : nil
    default: return nil
    }
  }
  public static func pointURL(_ configuration: WeatherConfiguration) throws -> URL {
    guard configuration.valid, configuration.provider == "nws" else {
      throw WeatherError.invalidConfiguration
    }
    let point = String(
      format: "%.2f,%.2f", locale: Locale(identifier: "en_US_POSIX"), configuration.latitude,
      configuration.longitude)
    return URL(string: "https://api.weather.gov/points/" + point)!
  }
  public static func point(_ data: Data) throws -> NWSPoint {
    let p = try properties(data)
    func url(_ key: String, suffix: String) throws -> URL {
      guard let raw = p[key] as? String, let value = URL(string: raw),
        ForecastService.nws.allows(value), value.path.hasPrefix("/gridpoints/"),
        value.path.hasSuffix(suffix), value.query == nil
      else { throw WeatherError.invalidResponse }
      return value
    }
    return try NWSPoint(
      forecast: url("forecast", suffix: "/forecast"),
      hourly: url("forecastHourly", suffix: "/forecast/hourly"),
      stations: url("observationStations", suffix: "/stations"),
      timezone: (p["timeZone"] as? String).flatMap { TimeZone(identifier: $0) != nil ? $0 : nil })
  }
  public static func stations(_ data: Data, latitude: Double, longitude: Double) throws
    -> [NWSStation]
  {
    let root = try object(data)
    guard root["type"] as? String == "FeatureCollection",
      let features = root["features"] as? [[String: Any]], features.count <= 2000
    else { throw WeatherError.invalidResponse }
    var results: [NWSStation] = [], seen: Set<String> = []
    for feature in features {
      guard let p = feature["properties"] as? [String: Any],
        let id = p["stationIdentifier"] as? String, (1...32).contains(id.utf8.count),
        id.utf8.allSatisfy({
          (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
            || $0 == 95
        }), let geometry = feature["geometry"] as? [String: Any],
        geometry["type"] as? String == "Point",
        let coordinates = geometry["coordinates"] as? [NSNumber], coordinates.count == 2,
        let lon = number(coordinates[0]), let lat = number(coordinates[1]),
        (-90...90).contains(lat), (-180...180).contains(lon), seen.insert(id).inserted
      else { continue }
      results.append(
        NWSStation(identifier: id, name: text(p["name"], limit: 128), latitude: lat, longitude: lon)
      )
    }
    func distance(_ station: NWSStation) -> Double {
      let radians = Double.pi / 180, dlat = (station.latitude - latitude) * radians,
        dlon = (station.longitude - longitude) * radians
      return pow(sin(dlat / 2), 2) + cos(latitude * radians) * cos(station.latitude * radians)
        * pow(sin(dlon / 2), 2)
    }
    return results.sorted { distance($0) < distance($1) }.prefix(3).map { $0 }
  }
  public static func observation(_ data: Data) throws -> NWSObservation {
    let p = try properties(data)
    guard let timestamp = date(p["timestamp"] as? String) else {
      throw WeatherError.invalidResponse
    }
    var observation = NWSObservation(
      date: timestamp, temperature: quantity(p["temperature"], kind: "temperature"),
      apparent: quantity(p["windChill"], kind: "temperature")
        ?? quantity(p["heatIndex"], kind: "temperature"),
      humidity: quantity(p["relativeHumidity"], kind: "percent"),
      wind: quantity(p["windSpeed"], kind: "wind"), gusts: quantity(p["windGust"], kind: "wind"),
      direction: quantity(p["windDirection"], kind: "direction"),
      pressure: quantity(p["barometricPressure"], kind: "pressure"),
      condition: (p["textDescription"] as? String).map { String($0.prefix(256)) })
    observation.icon = WeatherIconMetadata.nws(p["icon"] as? String)
    return observation
  }
  public static func forecast(_ data: Data, limit: Int) throws -> (
    periods: [WeatherPeriod], updated: Date?
  ) {
    let p = try properties(data)
    guard let periods = p["periods"] as? [[String: Any]], periods.count <= 2000 else {
      throw WeatherError.invalidResponse
    }
    var result: [WeatherPeriod] = []
    for period in periods.prefix(max(0, min(limit, 168))) {
      guard let start = date(period["startTime"] as? String),
        let end = date(period["endTime"] as? String), end > start,
        let isDay = period["isDaytime"] as? Bool
      else { throw WeatherError.invalidResponse }
      var temperature = quantity(period["temperature"], kind: "temperature")
      if let numeric = number(period["temperature"]) {
        let unit = period["temperatureUnit"] as? String
        temperature = unit == "C" ? numeric : unit == "F" ? (numeric - 32) / 1.8 : nil
      }
      result.append(
        WeatherPeriod(
          name: text(period["name"], limit: 128), start: start, end: end, isDay: isDay,
          temperature: temperature,
          precipitation: quantity(period["probabilityOfPrecipitation"], kind: "percent"),
          condition: text(period["shortForecast"], limit: 256),
          detail: text(period["detailedForecast"], limit: 4096),
          wind: [
            (period["windSpeed"] as? String).map { String($0.prefix(128)) }
              ?? quantity(period["windSpeed"], kind: "wind").map { String(format: "%.1f km/h", $0) }
              ?? "",
            text(period["windDirection"], limit: 32),
          ].filter { !$0.isEmpty }.joined(separator: " · "),
          glyph: WeatherIconMetadata.nws(period["icon"] as? String)?.glyph,
          humidity: quantity(period["relativeHumidity"], kind: "percent"),
          dewpoint: quantity(period["dewpoint"], kind: "temperature"),
          windSpeed: quantity(period["windSpeed"], kind: "wind"),
          gusts: quantity(period["windGust"], kind: "wind"),
          gustDescription: (period["windGust"] as? String).map { String($0.prefix(128)) }))
    }
    return (
      result.sorted { $0.start < $1.start },
      date(p["updated"] as? String ?? p["updateTime"] as? String)
    )
  }
}

public struct NWSProvider: WeatherProvider {
  public init() {}
  public func fetch(configuration: WeatherConfiguration) async throws -> WeatherReport {
    let client = ForecastHTTPClient(service: .nws); defer { client.close() }
    return try await fetch(configuration: configuration, transport: client)
  }
  public func fetch(
    configuration: WeatherConfiguration, transport: ForecastTransport, fetched: Date? = nil
  ) async throws -> WeatherReport {
    func read(_ url: URL) async throws -> Data {
      try Task.checkCancellation()
      let data = try await transport.data(url)
      try Task.checkCancellation(); return data
    }
    let point = try NWSWeather.point(await read(NWSWeather.pointURL(configuration)))
    var report = WeatherReport(
      source: "NWS", attributionURL: "https://www.weather.gov/", fetched: fetched ?? Date(),
      timeContext: WeatherTimeContext(identifier: point.timezone, offsetSeconds: nil), hours: [],
      days: [], alerts: [])
    do {
      let forecast = try NWSWeather.forecast(await read(point.forecast), limit: 14)
      report.periods = forecast.periods; report.forecastUpdated = forecast.updated
    } catch {
      try Task.checkCancellation(); report.notes.append("Named-period forecast unavailable.")
    }
    do {
      let hourly = try NWSWeather.forecast(await read(point.hourly), limit: 168)
      report.hours = hourly.periods.map {
        WeatherHour(
          date: $0.start, temperature: $0.temperature, precipitation: $0.precipitation, code: -1,
          condition: $0.condition, isDay: $0.isDay, glyph: $0.glyph, end: $0.end,
          humidity: $0.humidity, dewpoint: $0.dewpoint,
          wind: $0.windSpeed, gusts: $0.gusts, windDescription: $0.wind,
          gustDescription: $0.gustDescription, detail: $0.detail)
      }
    } catch { try Task.checkCancellation(); report.notes.append("Hourly forecast unavailable.") }
    do {
      let latitude = (configuration.latitude * 100).rounded() / 100,
        longitude = (configuration.longitude * 100).rounded() / 100
      let stations = try NWSWeather.stations(
        await read(point.stations), latitude: latitude, longitude: longitude)
      var partial: (NWSStation, NWSObservation)?
      for station in stations {
        do {
          let observation = try NWSWeather.observation(await read(station.observationURL))
          guard observation.isFresh(at: fetched ?? Date()) else {
            report.notes.append(
              "Station \(station.identifier) observation stale or future-dated; current values withheld."
            ); continue
          }
          if partial == nil || observation.temperature != nil { partial = (station, observation) }
          if observation.temperature != nil { break }
        } catch { try Task.checkCancellation() }
      }
      if let (station, observation) = partial {
        report.observationTime = observation.date;
        report.observationStation =
          station.identifier + (station.name.isEmpty ? "" : " · " + station.name)
        report.temperature = observation.temperature; report.apparent = observation.apparent
        report.humidity = observation.humidity; report.wind = observation.wind;
        report.gusts = observation.gusts
        report.direction = observation.direction; report.pressure = observation.pressure;
        report.condition = observation.condition
        report.glyph = observation.icon?.glyph; report.isDay = observation.icon?.isDay
      } else {
        report.notes.append("No fresh observation from the nearest three advertised stations.")
      }
    } catch {
      try Task.checkCancellation();
      report.notes.append("Station observations unavailable; forecasts remain distinct.")
    }
    do {
      let url = try WeatherAlerts.request(
        latitude: configuration.latitude, longitude: configuration.longitude)
      report.alertReport = try WeatherAlerts.parse(await read(url), fetched: fetched ?? Date())
    } catch {
      try Task.checkCancellation(); report.notes.append("Point alert messages unavailable.")
    }
    report.notes.append(
      "Station observations can be delayed. Forecast-period temperatures are not complete daily minima/maxima. Point alerts refresh with the forecast every 15 minutes."
    )
    report.fetched = fetched ?? Date()
    try Task.checkCancellation(); return report
  }
}
